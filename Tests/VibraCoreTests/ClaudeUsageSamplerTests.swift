import Foundation
import Testing
@testable import VibraCore

/// The one fold for "one API response, several records". Every rule is run
/// through both consumers: `Session.usage` via `SessionIngest` (the live
/// path) and the samples `ReportIngest` hands the report.
struct ClaudeUsageSamplerTests {

    // MARK: - Fixtures

    private func transcript(_ lines: [String], name: String = "s.jsonl") throws -> URL {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data().write(to: file)
        try append(lines, to: file)
        return file
    }

    private func append(_ lines: [String], to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.map { $0 + "\n" }.joined()).utf8))
    }

    private func record(
        id: String?,
        output: Int,
        input: Int = 10,
        cacheCreation: Int = 0,
        cacheRead: Int = 100,
        timestamp: String? = "2026-09-18T10:00:00.000Z",
        model: String? = "claude-opus-5",
        type: String = "assistant",
        sidechain: Bool = false,
        cwd: String? = "/Users/demo/proj",
        tools: [String] = []
    ) -> String {
        var message: [String: Any] = [
            "role": type == "assistant" ? "assistant" : "user",
            "content": tools.map { ["type": "tool_use", "name": $0, "input": ["path": "/SECRET/x"]] },
        ]
        if let id { message["id"] = id }
        if let model { message["model"] = model }
        if type == "assistant" {
            message["usage"] = [
                "input_tokens": input, "output_tokens": output,
                "cache_creation_input_tokens": cacheCreation, "cache_read_input_tokens": cacheRead,
            ]
        }
        var record: [String: Any] = ["type": type, "sessionId": "s", "message": message]
        if let timestamp { record["timestamp"] = timestamp }
        if let cwd { record["cwd"] = cwd }
        if sidechain { record["isSidechain"] = true }
        let data = try! JSONSerialization.data(withJSONObject: record)
        return String(decoding: data, as: UTF8.self)
    }

    private func usage(input: Int = 10, output: Int, cacheCreation: Int = 0, cacheRead: Int = 100) -> TokenUsage {
        TokenUsage(input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead)
    }

    private func iso(_ string: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string)!
    }

    // MARK: - The two consumers

    private func live(_ file: URL, maxLinesPerRead: Int = 2_000) async -> TokenUsage {
        let ingest = SessionIngest(
            adapters: [ClaudeCodeAdapter(file: file)],
            reader: IncrementalLineReader(maxLinesPerRead: maxLinesPerRead),
            horizon: nil
        )
        return await ingest.refresh().first?.usage ?? .zero
    }

    private func report(_ file: URL, maxLinesPerRead: Int = 2_000) async -> [UsageSample] {
        let ingest = ReportIngest(
            adapters: [ClaudeCodeAdapter(file: file)],
            reader: IncrementalLineReader(maxLinesPerRead: maxLinesPerRead)
        )
        let window = ReportWindow(now: Date(), days: 7, calendar: .current)
        return await ingest.collect(window: window).sources[.claudeCode]?.first?.samples ?? []
    }

    private func total(_ samples: [UsageSample]) -> TokenUsage {
        samples.reduce(.zero) { $0 + $1.usage }
    }

    // MARK: - Merging

    @Test func threeRecordsWithOneIDGiveTheLastUsage() async throws {
        let file = try transcript([
            record(id: "a", output: 5), record(id: "a", output: 9), record(id: "a", output: 14),
        ])
        let samples = await report(file)
        #expect(samples.count == 1)
        #expect(total(samples) == usage(output: 14))
        #expect(await live(file) == usage(output: 14))
    }

    @Test func pairSplitAcrossBatchesStillMerges() async throws {
        let file = try transcript([record(id: "a", output: 5), record(id: "a", output: 9)])
        let samples = await report(file, maxLinesPerRead: 1)
        #expect(samples.count == 1)
        #expect(total(samples) == usage(output: 9))
        #expect(await live(file, maxLinesPerRead: 1) == usage(output: 9))
    }

    @Test func pairSplitAcrossPollsStillMerges() async throws {
        let file = try transcript([record(id: "a", output: 5)])
        let ingest = SessionIngest(adapters: [ClaudeCodeAdapter(file: file)], horizon: nil)
        #expect(await ingest.refresh().first?.usage == usage(output: 5),
                "the pending response is counted while its records are still arriving")

        try append([record(id: "a", output: 9)], to: file)
        #expect(await ingest.refresh().first?.usage == usage(output: 9))

        let samples = await report(file)
        #expect(samples.count == 1)
        #expect(total(samples) == usage(output: 9))
    }

    @Test func recordsWithoutIDNeverMerge() async throws {
        let file = try transcript([record(id: nil, output: 5), record(id: nil, output: 9)])
        let samples = await report(file)
        #expect(samples.count == 2)
        #expect(total(samples) == usage(input: 20, output: 14, cacheRead: 200))
        #expect(await live(file) == usage(input: 20, output: 14, cacheRead: 200))
    }

    @Test func userRecordBetweenTwoRecordsOfOneIDDoesNotSplitThem() async throws {
        let file = try transcript([
            record(id: "a", output: 5),
            record(id: "a", output: 0, type: "user"),
            record(id: "a", output: 9),
        ])
        let samples = await report(file)
        #expect(samples.count == 1)
        #expect(total(samples) == usage(output: 9))
        #expect(await live(file) == usage(output: 9))
    }

    @Test func firstRecordWithoutTimestampTakesTheSeconds() async throws {
        let file = try transcript([
            record(id: "a", output: 5, timestamp: nil),
            record(id: "a", output: 9, timestamp: "2026-09-18T10:00:30.000Z"),
        ])
        let samples = await report(file)
        #expect(samples.map(\.timestamp) == [iso("2026-09-18T10:00:30.000Z")])
        #expect(await live(file) == usage(output: 9))
    }

    @Test func aMergedResponseKeepsItsFirstTimestamp() async throws {
        let file = try transcript([
            record(id: "a", output: 5, timestamp: "2026-09-18T10:00:00.000Z"),
            record(id: "a", output: 9, timestamp: "2026-09-18T10:00:30.000Z"),
        ])
        #expect(await report(file).map(\.timestamp) == [iso("2026-09-18T10:00:00.000Z")])
    }

    @Test func modelAndProjectTakeTheLatestNonNilValue() async throws {
        let file = try transcript([
            record(id: "a", output: 5, model: nil, cwd: nil),
            record(id: "a", output: 9, model: "claude-sonnet-5", cwd: "/Users/demo/proj"),
            record(id: "a", output: 14, model: nil, cwd: nil),
        ])
        let sample = try #require(await report(file).first)
        #expect(sample.model == "claude-sonnet-5")
        #expect(sample.project == "proj")
    }

    @Test func zeroUsageRecordContributesZero() async throws {
        let file = try transcript([
            record(id: "a", output: 5),
            record(id: "z", output: 0, input: 0, cacheRead: 0, model: "<synthetic>"),
            record(id: "b", output: 9),
        ])
        let samples = await report(file)
        #expect(samples.count == 3)
        #expect(samples[1].usage == .zero)
        #expect(total(samples) == usage(input: 20, output: 14, cacheRead: 200))
        #expect(await live(file) == usage(input: 20, output: 14, cacheRead: 200))
    }

    @Test func inlineSidechainRecordCountsInTotalsAndIsFlagged() async throws {
        let file = try transcript([
            record(id: "a", output: 5),
            record(id: "s", output: 9, sidechain: true),
        ])
        let samples = await report(file)
        #expect(samples.map(\.isSidechain) == [false, true])
        #expect(total(samples) == usage(input: 20, output: 14, cacheRead: 200))
        #expect(await live(file) == usage(input: 20, output: 14, cacheRead: 200))
    }

    @Test func sidechainStaysTrueOnceAnyRecordOfTheResponseSetIt() async throws {
        let file = try transcript([
            record(id: "a", output: 5, sidechain: true),
            record(id: "a", output: 9),
        ])
        #expect(await report(file).map(\.isSidechain) == [true])
    }

    @Test func toolNamesAccumulateAcrossTheResponseAndCarryNoInput() async throws {
        let file = try transcript([
            record(id: "a", output: 5, tools: ["Read", "Grep"]),
            record(id: "a", output: 9, tools: ["Glob"]),
        ])
        let sample = try #require(await report(file).first)
        #expect(sample.toolNames == ["Read", "Grep", "Glob"])
        #expect(!String(describing: sample).contains("SECRET"))
    }

    // MARK: - Random batch splits

    /// SplitMix64: the suite needs a seedable generator, and Swift's system
    /// one is not.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
    func liveAndReportTotalsAgreeUnderRandomBatchSplits(seed: UInt64) async throws {
        var rng = SplitMix64(state: seed)
        var lines: [String] = []
        var previous: String?
        for i in 0..<60 {
            let roll = Int.random(in: 0..<10, using: &rng)
            let id: String?
            if roll < 4, let previous { id = previous }
            else if roll < 8 { id = "m\(i)" }
            else { id = nil }
            previous = id
            lines.append(record(
                id: id,
                output: Int.random(in: 1...1_000, using: &rng),
                timestamp: Bool.random(using: &rng) ? "2026-09-18T10:00:00.000Z" : nil,
                sidechain: Int.random(in: 0..<5, using: &rng) == 0
            ))
            if Int.random(in: 0..<6, using: &rng) == 0 {
                lines.append(record(id: id, output: 0, type: "user"))
            }
        }
        let file = try transcript(lines)

        let unsplit = total(await report(file))
        let liveSplit = await live(file, maxLinesPerRead: Int.random(in: 1...7, using: &rng))
        let reportSplit = total(await report(file, maxLinesPerRead: Int.random(in: 1...7, using: &rng)))
        #expect(liveSplit == unsplit, "seed \(seed)")
        #expect(reportSplit == unsplit, "seed \(seed)")
    }

    // MARK: - Full parse past one read

    /// 1,250 responses of two records each: 2,500 lines, so one read stops
    /// at line 2,000, in the middle of response 1,000.
    @Test func longTranscriptIsReadToTheEndByBothPaths() async throws {
        var lines: [String] = []
        for i in 0..<1_250 {
            lines.append(record(id: "m\(i)", output: 5, input: 1, cacheRead: 3))
            lines.append(record(id: "m\(i)", output: 9, input: 1, cacheRead: 3))
        }
        let file = try transcript(lines)
        let expected = TokenUsage(input: 1_250, output: 1_250 * 9, cacheCreation: 0, cacheRead: 1_250 * 3)

        let session = try #require(ClaudeCodeAdapter(file: file).discoverSessions().first)
        #expect(session.usage == expected)

        let samples = await report(file)
        #expect(samples.count == 1_250)
        #expect(total(samples) == expected)
    }

    // MARK: - Project and subagent paths

    @Test func projectIsTheLastComponentOfCWDAndNoParentLeaks() async throws {
        let file = try transcript([record(id: "a", output: 5, cwd: "/a/SECRET/b/proj", tools: ["Read"])])
        let sample = try #require(await report(file).first)
        #expect(sample.project == "proj")
        #expect(!String(describing: sample).contains("SECRET"))
    }

    @Test func rootCWDGivesNoProject() async throws {
        let file = try transcript([record(id: "a", output: 5, cwd: "/")])
        #expect(try #require(await report(file).first).project == nil)
    }

    @Test func isSubagentFollowsTheDirectoryBelowTheProjectsRoot() {
        // A `subagents` component ABOVE the root must not count.
        let root = testScratchDirectory().appendingPathComponent("subagents/projects")
        let adapter = ClaudeCodeAdapter(projectsRoot: root)
        let agent = root.appendingPathComponent("proj/sess/subagents/agent-a1.jsonl")
        let main = root.appendingPathComponent("proj/sess.jsonl")

        #expect(adapter.makeUsageSampler(for: agent).isSubagent)
        #expect(!adapter.makeUsageSampler(for: main).isSubagent)
        #expect(!ClaudeCodeAdapter(file: agent).makeUsageSampler(for: agent).isSubagent,
                "the single-file entry point has no root")
    }

    @Test func reportIngestStampsIsSubagentOnEachSource() async throws {
        let root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        let main = root.appendingPathComponent("proj/sess.jsonl")
        let agent = root.appendingPathComponent("proj/sess/subagents/agent-a1.jsonl")
        for file in [main, agent] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((record(id: "a", output: 5) + "\n").utf8).write(to: file)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let window = ReportWindow(now: Date(), days: 7, calendar: .current)
        let input = await ReportIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)]).collect(window: window)
        let flags = Dictionary(uniqueKeysWithValues: (input.sources[.claudeCode] ?? []).map {
            ($0.url.lastPathComponent, $0.isSubagent)
        })
        #expect(flags == ["sess.jsonl": false, "agent-a1.jsonl": true])
        #expect(input.read.files == 2)
    }
}
