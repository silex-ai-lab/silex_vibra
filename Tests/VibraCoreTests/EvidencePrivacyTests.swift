import Foundation
import Testing
@testable import VibraCore

/// The evidence canary: command text, file paths, tool output and edit text are
/// read to reach an enum and must not survive. The Makefile checks this test by
/// its exact name.
struct EvidencePrivacyTests {
    typealias F = EvidenceFixtures

    private let command = "SENTINEL_COMMAND_4c1"
    private let path = "SENTINEL_PATH_8e2"
    private let output = "SENTINEL_OUTPUT_1d7"
    /// Sentinels that travel through the counting path: a test path, the removed
    /// text and the inserted text.
    private let testPath = "SENTINEL_TESTPATH_7d1"
    private let oldText = "SENTINEL_OLD_3e9"
    private let newText = "SENTINEL_NEW_6c2"

    private func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }

    @Test func evidenceSentinelsNeverLeak() async throws {
        let root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let claudeRoot = root.appendingPathComponent("claude")
        let codexRoot = root.appendingPathComponent("codex")

        // A source edit, then the existing command/build/lint sentinels, then a
        // failed test run, then test-path edits (Edit and MultiEdit counted, a
        // Write on another test file with nil counts), then the passing run.
        let testFile = "/work/tests/\(testPath)AppTests.swift"
        let claudeLines = [
            F.claudeEdit("e0", path: "/work/\(path)/App.swift", cwd: "/work", at: 0),
            F.claudeResult("e0", text: "ok", at: 1),
            F.claudeBash("t1", "swift test --filter \(command) | tail -3", at: 2),
            F.claudeResult("t1", text: "Test run with 2 tests passed \(output)", at: 3),
            F.claudeBash("t2", "swift build --target \(command)", at: 4),
            F.claudeResult("t2", text: "Exit code 1\n\(output)", isError: true, at: 5),
            F.claudeBash("t3", "make lint \(command)", at: 6),
            F.claudeBash("t4", "swift test", at: 8),
            F.claudeResult("t4", text: "Exit code 1\nTest run with 3 tests failed", isError: true, at: 9),
            F.claudeEdit(
                "e1", path: testFile, old: "XCTAssert(\(oldText))", new: "// \(newText)",
                cwd: "/work", at: 10),
            F.claudeResult("e1", text: "ok", at: 11),
            F.claudeMultiEdit(
                "e2", path: testFile,
                edits: [(old: "XCTAssertEqual(a, b) // \(oldText)", new: "// \(newText)")],
                cwd: "/work", at: 12),
            F.claudeResult("e2", text: "ok", at: 13),
            F.claudeEdit("e3", path: "/work/tests/\(testPath)OtherTests.swift", name: "Write", cwd: "/work", at: 14),
            F.claudeResult("e3", text: "ok", at: 15),
            F.claudeBash("t5", "swift test", at: 20),
            F.claudeResult("t5", text: "Test run with 3 tests passed", at: 21),
        ]
        try write(claudeLines, to: claudeRoot.appendingPathComponent("proj/sess-1.jsonl"))
        let codexLines = [
            F.codexMeta(cwd: "/work", at: 0),
            F.codexCommand("swift test --filter \(command) | tail", exit: 1, output: "failed \(output)", at: 1),
            F.codexCommand("swift build \(command)", exit: 0, output: output, at: 2),
            F.codexChange(["/work/tests/\(testPath)Codex.swift"], at: 5),
            F.codexCommand("swift test --filter \(command) | tail", exit: 0, output: "Test run with 2 tests passed", at: 10),
        ]
        try write(codexLines, to: codexRoot.appendingPathComponent("2026/11/08/rollout-a-root-1.jsonl"))

        let ingest = EvidenceIngest(adapters: [
            ClaudeCodeAdapter(projectsRoot: claudeRoot), CodexAdapter(sessionsRoot: codexRoot),
        ])
        var rows: [(agent: AgentKind, fold: EvidenceFold)] = []
        var rendered: [String] = []
        var claudeLine = ""
        for (agent, id) in [(AgentKind.claudeCode, "sess-1"), (.codex, "root-1")] {
            let session = Session(id: id, agent: agent, cwd: "/work", startedAt: F.at(0), lastActivity: F.at(30))
            let fold = try #require(await ingest.collect(for: session))
            #expect(!fold.events.isEmpty)
            let evidence = DeliveryEvidence.build(events: fold.events, sawToolRecords: fold.sawToolRecords)
            rows.append((agent, fold))
            let line = evidence.line(now: F.at(100))
            if agent == .claudeCode { claudeLine = line }
            rendered += [String(describing: fold), String(describing: evidence), line]
        }
        rendered.append(EvidenceStats.format(rows))

        var claude = ClaudeEvidenceExtractor()
        claude.fold(claudeLines)
        var codex = CodexEvidenceExtractor()
        codex.fold(codexLines)
        rendered += [String(describing: claude), String(describing: codex)]
        rendered += [String(describing: claude.finish()), String(describing: codex.finish())]

        // Without this the rest proves nothing: the sentinel-bearing text has to
        // have gone through the counting path, not been skipped.
        #expect(claudeLine.contains("fewer assertion matches"))

        for text in rendered {
            for sentinel in [command, path, output, testPath, oldText, newText] {
                #expect(!text.contains(sentinel))
            }
        }
    }
}
