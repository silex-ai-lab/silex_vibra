import Foundation
import Testing
@testable import VibraCore

/// A row in the menu is one session a person can act on. Agents write extra
/// transcripts that reuse a session's id, and the menu must survive all of them.
struct SessionIdentityTests {
    private let rootStamp = "2026-11-08T10:00:00.000Z"
    private let laterStamp = "2026-11-08T10:30:00.000Z"

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((text + "\n").utf8).write(to: file)
    }

    private func scratchRoot() -> URL {
        testScratchDirectory().appendingPathComponent(UUID().uuidString)
    }

    private func codexMeta(id: String, stamp: String, source: String) -> String {
        #"{"timestamp":"\#(stamp)","type":"session_meta","payload":{"session_id":"root-1","id":"\#(id)","cwd":"/tmp/proj","originator":"codex-tui","source":\#(source)}}"#
    }

    private func claudeRecord(sessionID: String, stamp: String) -> String {
        #"{"type":"user","sessionId":"\#(sessionID)","timestamp":"\#(stamp)","cwd":"/tmp/proj","message":{"role":"user","content":"hi"}}"#
    }

    private func writeCodexRollouts(under root: URL) throws {
        try write(
            codexMeta(id: "root-1", stamp: rootStamp, source: #""cli""#),
            to: root.appendingPathComponent("2026/11/08/rollout-a-root-1.jsonl"))
        try write(
            codexMeta(
                id: "thread-2", stamp: laterStamp,
                source: #"{"subagent":{"thread_spawn":{"parent_thread_id":"root-1","depth":1}}}"#),
            to: root.appendingPathComponent("2026/11/08/rollout-b-thread-2.jsonl"))
        try write(
            codexMeta(id: "thread-3", stamp: laterStamp, source: #"{"subagent":{"other":"guardian"}}"#),
            to: root.appendingPathComponent("2026/11/08/rollout-c-thread-3.jsonl"))
    }

    @Test func codexSubagentThreadsAreNotSessions() async throws {
        let root = scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeCodexRollouts(under: root)

        let sessions = await SessionIngest(adapters: [CodexAdapter(sessionsRoot: root)], horizon: nil).refresh()

        #expect(sessions.map(\.id) == ["root-1"])
        #expect(sessions.first?.lastActivity == parseISODate(rootStamp))
    }

    @Test func codexSubagentUsageStillReachesTheReport() async throws {
        let root = scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeCodexRollouts(under: root)

        let window = ReportWindow(now: Date(), days: 7, calendar: .current)
        let input = await ReportIngest(adapters: [CodexAdapter(sessionsRoot: root)]).collect(window: window)

        #expect(input.read.files == 3)
    }

    @Test func claudeSubagentTranscriptsAreNotSessions() async throws {
        let root = scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            claudeRecord(sessionID: "sess-1", stamp: rootStamp),
            to: root.appendingPathComponent("proj/sess-1.jsonl"))
        try write(
            claudeRecord(sessionID: "sess-1", stamp: laterStamp),
            to: root.appendingPathComponent("proj/sess-1/subagents/agent-a1.jsonl"))
        let adapter = ClaudeCodeAdapter(projectsRoot: root)

        let sessions = await SessionIngest(adapters: [adapter], horizon: nil).refresh()

        #expect(sessions.map(\.id) == ["sess-1"])
        #expect(sessions.first?.lastActivity == parseISODate(rootStamp))
        #expect(try adapter.discoverSessions().map(\.id) == ["sess-1"])
    }

    @Test func twoTranscriptsClaimingOneSessionBecomeOneMenuRow() async throws {
        let root = scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            claudeRecord(sessionID: "moved-1", stamp: rootStamp),
            to: root.appendingPathComponent("old-proj/moved-1.jsonl"))
        try write(
            claudeRecord(sessionID: "moved-1", stamp: laterStamp),
            to: root.appendingPathComponent("new-proj/moved-1.jsonl"))

        let sessions = await SessionIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)], horizon: nil).refresh()
        let menu = SessionMenuModel.build(StatusSnapshot(sessions: sessions), now: Date())

        #expect(sessions.map(\.lastActivity) == [parseISODate(laterStamp)])
        #expect(menu.detailRows.count == 1)
    }
}
