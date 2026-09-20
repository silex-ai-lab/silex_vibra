import Foundation
import Testing
@testable import VibraCore

/// Proves the incremental ingest path (`sources()` + `update(...)`) produces
/// exactly what the full parse produces, and that reset / torn-line handling
/// are correct end-to-end through `SessionIngest`.
struct IncrementalIngestTests {

    private func fixtureLines(_ name: String) throws -> [String] {
        let url = fixtureURL("Fixtures/\(name)")
        return try IncrementalLineReader().read(url: url, from: 0).lines
    }

    /// Folds a fixture in two halves and returns the final parsed state.
    private func folded(_ adapter: any AgentAdapter, fixture: String) throws -> ParsedState {
        let url = fixtureURL("Fixtures/\(fixture)")
        let source = try #require(SourceDescriptor.describing(url))
        let lines = try fixtureLines(fixture)
        let mid = lines.count / 2
        let first = Array(lines[..<mid])
        let second = Array(lines[mid...])
        let a = try adapter.update(source: source, input: .records(first, reset: true), previous: nil)
        return try adapter.update(source: source, input: .records(second, reset: false), previous: a)
    }

    private func append(_ data: Data, to url: URL) throws {
        let existing = (try? Data(contentsOf: url)) ?? Data()
        var combined = existing
        combined.append(data)
        try combined.write(to: url)
    }

    @Test func claudeFoldingMatchesFullParse() throws {
        let url = fixtureURL("Fixtures/claude_session.jsonl")
        let adapter = ClaudeCodeAdapter(file: url)

        let fullSession = try #require(adapter.discoverSessions().first)
        let foldedSession = try #require(folded(adapter, fixture: "claude_session.jsonl").sessions.first)

        #expect(foldedSession.id == fullSession.id)
        #expect(foldedSession.cwd == fullSession.cwd)
        #expect(foldedSession.lastEvent == fullSession.lastEvent)
        #expect(foldedSession.usage == fullSession.usage)
        #expect(foldedSession == fullSession)
    }

    @Test func codexFoldingMatchesFullParse() throws {
        let url = fixtureURL("Fixtures/codex_rollout.jsonl")
        let adapter = CodexAdapter(file: url)

        let fullSession = try #require(adapter.discoverSessions().first)
        let foldedSession = try #require(folded(adapter, fixture: "codex_rollout.jsonl").sessions.first)

        #expect(foldedSession.id == fullSession.id)
        #expect(foldedSession.cwd == fullSession.cwd)
        #expect(foldedSession.lastEvent == fullSession.lastEvent)
        #expect(foldedSession.usage == fullSession.usage)
        #expect(foldedSession == fullSession)
    }

    @Test func shrinkCausesResetAndDropsStaleTotals() async throws {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.jsonl")

        let big = """
        {"type":"system","sessionId":"s1","timestamp":"2026-09-18T10:00:00.000Z","cwd":"/x","gitBranch":"main"}
        {"type":"assistant","sessionId":"s1","timestamp":"2026-09-18T10:00:05.000Z","cwd":"/x","message":{"model":"claude-opus-5","stop_reason":"end_turn","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        {"type":"assistant","sessionId":"s1","timestamp":"2026-09-18T10:00:06.000Z","cwd":"/x","message":{"model":"claude-opus-5","stop_reason":"end_turn","usage":{"input_tokens":50,"output_tokens":60,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try (big + "\n").write(to: file, atomically: false, encoding: .utf8)

        let ingest = SessionIngest(adapters: [ClaudeCodeAdapter(file: file)])
        let first = await ingest.refresh()
        #expect(first.first?.usage == TokenUsage(input: 150, output: 260, cacheCreation: 0, cacheRead: 0))

        // Truncate to a shorter transcript with a single smaller assistant
        // record. Size goes backwards, so the ingest layer must reset rather
        // than fold the stale 150/260 total into the new file.
        let small = """
        {"type":"system","sessionId":"s1","timestamp":"2026-09-18T10:00:00.000Z","cwd":"/x","gitBranch":"main"}
        {"type":"assistant","sessionId":"s1","timestamp":"2026-09-18T10:00:05.000Z","cwd":"/x","message":{"model":"claude-opus-5","stop_reason":"end_turn","usage":{"input_tokens":7,"output_tokens":8,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try (small + "\n").write(to: file, atomically: false, encoding: .utf8)

        let second = await ingest.refresh()
        #expect(second.first?.usage == TokenUsage(input: 7, output: 8, cacheCreation: 0, cacheRead: 0))
    }

    @Test func tornLineThenCompletionYieldsOneRecord() async throws {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")

        // One full record, cut in half: the first half has no newline and is
        // not yet a parseable record.
        let full = #"{"type":"assistant","sessionId":"t1","timestamp":"2026-09-18T10:00:00.000Z","cwd":"/x","message":{"model":"claude-opus-5","stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        let cut = full.index(full.startIndex, offsetBy: full.count / 2)
        try Data(full[..<cut].utf8).write(to: file)

        let ingest = SessionIngest(adapters: [ClaudeCodeAdapter(file: file)])
        let first = await ingest.refresh()
        #expect(first.isEmpty)

        // Complete the line.
        try append(Data(full[cut...].utf8) + Data([0x0A]), to: file)

        let second = await ingest.refresh()
        #expect(second.count == 1)
        #expect(second.first?.usage == TokenUsage(input: 1, output: 2, cacheCreation: 0, cacheRead: 0))
    }
}
