import Foundation
import Testing
@testable import VibraCore

struct UsageSampleTests {
    private func fixtureLines(_ name: String) throws -> [String] {
        let url = fixtureURL("Fixtures/\(name)")
        return try IncrementalLineReader().read(url: url, from: 0).lines
    }

    @Test func claudeSamplesSumToAggregate() throws {
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/claude_session.jsonl"))
        let records = try fixtureLines("claude_session.jsonl")
        let samples = adapter.usageSamples(from: records)

        let aggregate = try #require(adapter.discoverSessions().first).usage
        let sum = samples.reduce(TokenUsage.zero) { $0 + $1.usage }

        #expect(samples.count == 2)
        #expect(sum == aggregate)
        #expect(sum == TokenUsage(input: 15, output: 500, cacheCreation: 1000, cacheRead: 11000))
    }

    @Test func codexSamplesSumToFinalCumulative() throws {
        let adapter = CodexAdapter(file: fixtureURL("Fixtures/codex_rollout.jsonl"))
        let records = try fixtureLines("codex_rollout.jsonl")
        let samples = adapter.usageSamples(from: records)

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
        let samples = adapter.usageSamples(from: records)
        let timestamps = samples.compactMap { $0.timestamp }

        #expect(timestamps.count == 3)
        #expect(timestamps == timestamps.sorted())

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(Set(timestamps.map { calendar.startOfDay(for: $0) }).count == 3)
    }

    @Test func openCodeReturnsNoSamples() {
        let adapter = OpenCodeAdapter(dbURL: fixtureURL("Fixtures/claude_session.jsonl"))
        #expect(adapter.usageSamples(from: ["any", "records"]) == [])
    }

    @Test func noSingleSampleEqualsAggregate() throws {
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/claude_session.jsonl"))
        let records = try fixtureLines("claude_session.jsonl")
        let samples = adapter.usageSamples(from: records)
        let aggregate = try #require(adapter.discoverSessions().first).usage

        #expect(samples.count > 1)
        for sample in samples {
            #expect(sample.usage != aggregate)
        }
    }
}
