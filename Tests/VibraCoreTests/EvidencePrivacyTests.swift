import Foundation
import Testing
@testable import VibraCore

/// The evidence canary: command text, file paths and tool output are read to
/// reach an enum and must not survive. The Makefile checks this test by its
/// exact name.
struct EvidencePrivacyTests {
    typealias F = EvidenceFixtures

    private let command = "SENTINEL_COMMAND_4c1"
    private let path = "SENTINEL_PATH_8e2"
    private let output = "SENTINEL_OUTPUT_1d7"

    private func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }

    @Test func evidenceSentinelsNeverLeak() async throws {
        let root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let claudeRoot = root.appendingPathComponent("claude")
        let codexRoot = root.appendingPathComponent("codex")

        let claudeLines = [
            F.claudeEdit("e1", path: "/work/\(path)/App.swift", at: 1), F.claudeResult("e1", text: "ok", at: 2),
            F.claudeBash("t1", "swift test --filter \(command) | tail -3", at: 3),
            F.claudeResult("t1", text: "Test run with 2 tests passed \(output)", at: 4),
            F.claudeBash("t2", "swift build --target \(command)", at: 5),
            F.claudeResult("t2", text: "Exit code 1\n\(output)", isError: true, at: 6),
            F.claudeBash("t3", "make lint \(command)", at: 7),
        ]
        try write(claudeLines, to: claudeRoot.appendingPathComponent("proj/sess-1.jsonl"))
        let codexLines = [
            #"{"timestamp":"\#(F.stamp(0))","type":"session_meta","payload":{"session_id":"root-1","id":"root-1"}}"#,
            F.codexChange(["/work/\(path)/b.swift"], at: 1),
            F.codexCommand("swift test --filter \(command) | tail", exit: 1, output: "failed \(output)", at: 3),
            F.codexCommand("swift build \(command)", exit: 0, output: output, at: 5),
        ]
        try write(codexLines, to: codexRoot.appendingPathComponent("2026/11/08/rollout-a-root-1.jsonl"))

        let ingest = EvidenceIngest(adapters: [
            ClaudeCodeAdapter(projectsRoot: claudeRoot), CodexAdapter(sessionsRoot: codexRoot),
        ])
        var rows: [(agent: AgentKind, fold: EvidenceFold)] = []
        var rendered: [String] = []
        for (agent, id) in [(AgentKind.claudeCode, "sess-1"), (.codex, "root-1")] {
            let session = Session(id: id, agent: agent, cwd: "/work", startedAt: F.at(0), lastActivity: F.at(10))
            let fold = try #require(await ingest.collect(for: session))
            #expect(!fold.events.isEmpty)
            let evidence = DeliveryEvidence.build(events: fold.events, sawToolRecords: fold.sawToolRecords)
            rows.append((agent, fold))
            rendered += [String(describing: fold), String(describing: evidence), evidence.line(now: F.at(100))]
        }
        rendered.append(EvidenceStats.format(rows))

        var claude = ClaudeEvidenceExtractor()
        claude.fold(claudeLines)
        var codex = CodexEvidenceExtractor()
        codex.fold(codexLines)
        rendered += [String(describing: claude), String(describing: codex)]
        rendered += [String(describing: claude.finish()), String(describing: codex.finish())]

        for text in rendered {
            for sentinel in [command, path, output] {
                #expect(!text.contains(sentinel))
            }
        }
    }
}
