import Foundation
import Testing
@testable import VibraCore

struct UsageSampleTests {
    private func fixtureLines(_ name: String) throws -> [String] {
        let url = fixtureURL("Fixtures/\(name)")
        return try IncrementalLineReader().read(url: url, from: 0).lines
    }

    private func samples(_ adapter: any AgentAdapter, _ lines: [String]) -> [UsageSample] {
        var sampler = adapter.makeUsageSampler(for: fixtureURL("Fixtures/any.jsonl"))
        return sampler.add(lines) + sampler.finish()
    }

    private func iso(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    @Test func claudeSamplesSumToAggregate() throws {
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/claude_session.jsonl"))
        let samples = samples(adapter, try fixtureLines("claude_session.jsonl"))

        let aggregate = try #require(adapter.discoverSessions().first).usage
        let sum = samples.reduce(TokenUsage.zero) { $0 + $1.usage }

        #expect(samples.count == 2)
        #expect(sum == aggregate)
        #expect(sum == TokenUsage(input: 15, output: 500, cacheCreation: 1000, cacheRead: 11000))
    }

    @Test func codexSamplesSumToFinalCumulative() throws {
        let adapter = CodexAdapter(file: fixtureURL("Fixtures/codex_rollout.jsonl"))
        let samples = samples(adapter, try fixtureLines("codex_rollout.jsonl"))

        let sum = samples.reduce(TokenUsage.zero) { $0 + $1.usage }

        // Per-turn usage sums to the FINAL cumulative, not the sum of the
        // cumulative values (which would be input 3500 / cached 1700 /
        // output 450). This is the multi-day multi-count trap.
        #expect(sum == TokenUsage(input: 2500, output: 350, cacheCreation: 0, cacheRead: 1300))
    }

    @Test func multiDaySamplesCarryDistinctOrderedTimestamps() {
        let records = [
            #"{"type":"assistant","timestamp":"2026-09-18T12:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#,
            #"{"type":"assistant","timestamp":"2026-09-19T12:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#,
            #"{"type":"assistant","timestamp":"2026-09-20T12:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#,
        ]
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/claude_session.jsonl"))
        let timestamps = samples(adapter, records).compactMap { $0.timestamp }

        #expect(timestamps.count == 3)
        #expect(timestamps == timestamps.sorted())

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(Set(timestamps.map { calendar.startOfDay(for: $0) }).count == 3)
    }

    @Test func openCodeReturnsNoSamples() {
        let adapter = OpenCodeAdapter(dbURL: fixtureURL("Fixtures/claude_session.jsonl"))
        #expect(samples(adapter, ["any", "records"]) == [])
        #expect(adapter.reportsUndatedTotals)
    }

    @Test func noSingleSampleEqualsAggregate() throws {
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/claude_session.jsonl"))
        let samples = samples(adapter, try fixtureLines("claude_session.jsonl"))
        let aggregate = try #require(adapter.discoverSessions().first).usage

        #expect(samples.count > 1)
        for sample in samples {
            #expect(sample.usage != aggregate)
        }
    }

    // MARK: - Full parse past one read

    /// A 2,500-line rollout: 1 `session_meta` naming the model, then 2,499
    /// `token_usage_record`s. One `IncrementalLineReader.read` stops at
    /// 2,000 lines, so both paths have to keep going, and the sampler has to
    /// remember the model it read on line 1.
    @Test func longCodexRolloutIsReadToTheEndAndStaysPriced() async throws {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("rollout-long.jsonl")

        let now = iso("2026-11-03T21:00:00Z")
        let perTurn = (input: 100, output: 10, cached: 50)
        let turns = 2_499
        var lines = [
            #"{"timestamp":"2026-11-03T10:00:00.000Z","type":"session_meta","payload":{"session_id":"long","cwd":"/Users/demo/proj","model":"gpt-5.6","model_provider":"openai"}}"#,
        ]
        for i in 1...turns {
            let stamp = ISO8601DateFormatter().string(from: iso("2026-11-03T10:00:00Z").addingTimeInterval(Double(i)))
            lines.append(
                #"{"timestamp":"\#(stamp)","type":"token_usage_record","payload":{"usage":{"input_tokens":\#(perTurn.input),"cached_input_tokens":\#(perTurn.cached),"cache_write_input_tokens":0,"output_tokens":\#(perTurn.output)},"thread_token_usage":{"input_tokens":\#(perTurn.input * i),"cached_input_tokens":\#(perTurn.cached * i),"cache_write_input_tokens":0,"output_tokens":\#(perTurn.output * i)}}}"#
            )
        }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: false, encoding: .utf8)

        let expected = TokenUsage(input: perTurn.input * turns, output: perTurn.output * turns,
                                  cacheCreation: 0, cacheRead: perTurn.cached * turns)
        let adapter = CodexAdapter(file: file)
        #expect(try #require(adapter.discoverSessions().first).usage == expected)

        let window = ReportWindow(now: now, days: 7, calendar: .current)
        let input = await ReportIngest(adapters: [adapter]).collect(window: window)
        let samples = try #require(input.sources[.codex]?.first?.samples)
        #expect(samples.count == turns)
        #expect(samples.reduce(TokenUsage.zero) { $0 + $1.usage } == expected)
        #expect(samples[2_100].model == "gpt-5.6", "a sample after line 2,000 still carries the session_meta model")

        let report = ReportBuilder().build(samplesByAgent: input.samplesByAgent, window: window)
        let codex = try #require(report.agents.first { $0.agent == .codex })
        #expect(codex.unpricedTokens == 0)
        // gpt-5.6: $1.25 input, $10 output, $0.125 cache read, per million.
        let value = Double(turns) * (Double(perTurn.input) * 1.25 + Double(perTurn.output) * 10.0
                                     + Double(perTurn.cached) * 0.125) / 1e6
        #expect(abs(codex.estimatedValue - value) < 1e-9)
    }
}
