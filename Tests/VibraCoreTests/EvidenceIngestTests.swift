import Foundation
import Testing
@testable import VibraCore

struct EvidenceIngestTests {
    typealias F = EvidenceFixtures

    private func scratch() -> URL { testScratchDirectory().appendingPathComponent(UUID().uuidString) }

    private func write(_ lines: [String], to file: URL, modified: Date? = nil) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path) }
    }

    private func session(_ agent: AgentKind, id: String, started: TimeInterval = 0) -> Session {
        Session(id: id, agent: agent, cwd: "/work", startedAt: F.at(started), lastActivity: F.at(started + 100))
    }

    // MARK: Claude Code

    private func claudeTree(under root: URL) throws {
        let project = root.appendingPathComponent("proj")
        try write([
            F.claudeEdit("e1", at: 1), F.claudeResult("e1", text: "ok", at: 2),
        ], to: project.appendingPathComponent("sess-1.jsonl"))
        try write([
            F.claudeBash("t1", "swift test", at: 10), F.claudeResult("t1", text: "ok", at: 11),
        ], to: project.appendingPathComponent("sess-1/subagents/agent-a.jsonl"))
        try write([
            F.claudeEdit("e9", at: 50), F.claudeResult("e9", text: "ok", at: 51),
        ], to: project.appendingPathComponent("sess-2.jsonl"))
        try write([
            F.claudeEdit("e8", at: 60), F.claudeResult("e8", text: "ok", at: 61),
        ], to: project.appendingPathComponent("sess-2/subagents/agent-b.jsonl"))
    }

    @Test func claudeFoldsTheRootAndItsOwnSubagentsOnly() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try claudeTree(under: root)
        let ingest = EvidenceIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)])

        let fold = await ingest.collect(for: session(.claudeCode, id: "sess-1"))

        #expect(fold?.events.count == 2)
        #expect(fold?.events.contains(.codeChange(F.at(1))) == true)
        #expect(fold?.events.contains(.check(ObservedCheck(at: F.at(10), kind: .test, result: .passed(.exitStatus)))) == true)
        let bytes = await ingest.lastBytesRead
        #expect(bytes > 0)
    }

    @Test func claudeSubagentCheckAfterTheRootEditIsEvidence() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try claudeTree(under: root)
        let ingest = EvidenceIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)])

        let evidence = await ingest.evidence(for: session(.claudeCode, id: "sess-1"))

        #expect(evidence == .checkedAfterLastChange(ObservedCheck(at: F.at(10), kind: .test, result: .passed(.exitStatus))))
    }

    @Test func aTranscriptLongerThanOneBatchStillPairsItsCalls() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let filler = (0..<2_500).map { _ in #"{"type":"user","message":{"role":"user","content":"hi"}}"# }
        try write(
            [F.claudeEdit("e1", at: 1)] + filler + [F.claudeResult("e1", text: "ok", at: 2)],
            to: root.appendingPathComponent("proj/sess-1.jsonl"))
        let ingest = EvidenceIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)])

        let fold = await ingest.collect(for: session(.claudeCode, id: "sess-1"))

        #expect(fold?.events == [.codeChange(F.at(1))])
    }

    // MARK: Codex

    private func meta(id: String, root: String) -> String {
        #"{"timestamp":"\#(F.stamp(0))","type":"session_meta","payload":{"session_id":"\#(root)","id":"\#(id)","cwd":"/work"}}"#
    }

    private func codexTree(under root: URL) throws {
        let day = root.appendingPathComponent("2026/11/08")
        try write([
            meta(id: "root-1", root: "root-1"), F.codexChange(["/work/a.swift"], at: 5),
        ], to: day.appendingPathComponent("rollout-a-root-1.jsonl"), modified: F.at(20))
        try write([
            meta(id: "child-2", root: "root-1"), F.codexCommand("swift test", exit: 0, at: 15),
        ], to: day.appendingPathComponent("rollout-b-child-2.jsonl"), modified: F.at(20))
        try write([
            meta(id: "other-3", root: "other"), F.codexCommand("swift build", exit: 1, at: 16),
        ], to: day.appendingPathComponent("rollout-c-other-3.jsonl"), modified: F.at(20))
        try write([
            meta(id: "old-4", root: "root-1"), F.codexCommand("swift build", exit: 1, at: -500),
        ], to: day.appendingPathComponent("rollout-d-old-4.jsonl"), modified: F.at(-400))
        try write(["not json"], to: day.appendingPathComponent("rollout-e-bare-5.jsonl"), modified: F.at(20))
    }

    @Test func codexFoldsTheRootAndSubagentRolloutsOfThisSession() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try codexTree(under: root)
        let ingest = EvidenceIngest(adapters: [CodexAdapter(sessionsRoot: root)])

        let evidence = await ingest.evidence(for: session(.codex, id: "root-1", started: 0))

        #expect(evidence == .checkedAfterLastChange(ObservedCheck(at: F.at(15), kind: .test, result: .passed(.exitStatus))))
    }

    // MARK: Agents without an extractor

    @Test func anAgentWithoutAnExtractorYieldsNothing() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try claudeTree(under: root)
        let ingest = EvidenceIngest(adapters: [ClaudeCodeAdapter(projectsRoot: root)])

        #expect(await ingest.collect(for: session(.cursor, id: "sess-1")) == nil)
        #expect(await ingest.evidence(for: session(.cursor, id: "sess-1")) == nil)
    }

    @Test func coverageNamesTheAdaptersWithExtractors() {
        let adapters: [any AgentAdapter] = [
            ClaudeCodeAdapter(), CodexAdapter(), OpenCodeAdapter(), CursorAdapter(), VSCodeAdapter(), HermesAdapter(),
        ]
        let withExtractor = adapters.filter { $0.evidenceExtractor() != nil }.map(\.kind)
        #expect(Set(withExtractor) == Set(EvidenceCoverage.agents))
    }
}
