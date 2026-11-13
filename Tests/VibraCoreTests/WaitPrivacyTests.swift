import Foundation
import Testing
@testable import VibraCore

/// The wait canary: prompt text, tool input, tool result, the agent's reply,
/// a cwd, a session id and a directory and file name all carry sentinels, and
/// none of them may reach `--wait-stats` or survive in a `WaitFold`. The
/// Makefile checks this test by its exact name.
struct WaitPrivacyTests {
    private let prompt = "SENTINEL_PROMPT_2b7"
    private let input = "SENTINEL_INPUT_6e4"
    private let result = "SENTINEL_RESULT_9c1"
    private let reply = "SENTINEL_REPLY_4a8"
    private let cwd = "SENTINEL_CWD_5f3"
    private let sessionID = "SENTINEL_SID_1d6"
    private let path = "SENTINEL_PATH_8b2"

    private func sentinels() -> [String] {
        [prompt, input, result, reply, cwd, sessionID, path]
    }

    private func at(_ minutesSeconds: String) -> String { "2026-11-10T10:\(minutesSeconds).000Z" }

    private func time(_ minutesSeconds: String) -> EpochMs {
        guard let ms = epochMs(fromTimestamp: at(minutesSeconds)) else {
            fatalError("test stamp \(at(minutesSeconds)) must parse")
        }
        return ms
    }

    private func json(_ record: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
    }

    private func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }

    // MARK: - Synthetic transcripts

    private func claudeUser(
        _ content: Any, at stamp: String, extra: [String: Any] = [:]
    ) -> String {
        var record: [String: Any] = [
            "type": "user", "sessionId": sessionID, "cwd": "/work/\(cwd)", "entrypoint": "cli",
            "timestamp": stamp, "message": ["role": "user", "content": content],
        ]
        record.merge(extra) { $1 }
        return json(record)
    }

    private func claudeAssistant(
        _ blocks: [[String: Any]], stop: String, id: String, at stamp: String
    ) -> String {
        json([
            "type": "assistant", "sessionId": sessionID, "cwd": "/work/\(cwd)",
            "timestamp": stamp,
            "message": ["id": id, "role": "assistant", "content": blocks, "stop_reason": stop],
        ])
    }

    private func codex(_ type: String, _ payload: [String: Any], at stamp: String) -> String {
        json(["type": type, "payload": payload, "timestamp": stamp])
    }

    /// A Claude Code session with one turn wait, one question and one approval,
    /// and its prompt, tool input, tool result, reply, cwd and session id all
    /// sentinel-bearing.
    private func claudeTranscript() -> [String] {
        [
            // A prompt, a reply, and a second prompt: one turn wait.
            claudeUser("what does \(prompt) mean?", at: at("00:00")),
            claudeAssistant(
                [["type": "text", "text": "because \(reply)"]], stop: "end_turn", id: "m1",
                at: at("00:01")),
            claudeUser("and then \(prompt)?", at: at("00:02")),
            // A question dialog: input and result sentinels, one question wait.
            claudeAssistant(
                [[
                    "type": "tool_use", "id": "tu-question", "name": "AskUserQuestion",
                    "input": ["questions": [["question": input]]],
                ]], stop: "tool_use", id: "m2", at: at("00:03")),
            claudeUser(
                [["type": "tool_result", "tool_use_id": "tu-question", "content": result]],
                at: at("00:04"),
                extra: ["permissionDecision": ["decision": "accept", "source": "user"]]),
            // A user-answered command: one approval wait.
            claudeAssistant(
                [[
                    "type": "tool_use", "id": "tu-bash", "name": "Bash",
                    "input": ["command": input],
                ]], stop: "tool_use", id: "m3", at: at("00:05")),
            claudeUser(
                [["type": "tool_result", "tool_use_id": "tu-bash", "content": result]],
                at: at("00:06"),
                extra: ["permissionDecision": ["decision": "reject", "source": "user_temporary"]]),
            // A reply with nobody's prompt after it: the transcript ends waiting.
            claudeAssistant(
                [["type": "text", "text": "done: \(reply)"]], stop: "end_turn", id: "m4",
                at: at("00:07")),
        ]
    }

    /// A Codex session with one turn wait, its prompt, session id, cwd, tool
    /// input and reply all sentinel-bearing.
    private func codexTranscript() -> [String] {
        [
            codex("session_meta", [
                "session_id": sessionID, "cwd": "/work/\(cwd)", "originator": "codex-tui",
                "source": "cli",
            ], at: at("00:00")),
            codex("response_item", [
                "type": "message", "role": "user",
                "content": [["type": "input_text", "text": "please explain \(prompt)"]],
            ], at: at("00:30")),
            codex("event_msg", ["type": "task_complete"], at: at("01:00")),
            codex("response_item", [
                "type": "message", "role": "user",
                "content": [["type": "input_text", "text": "and \(prompt) again"]],
            ], at: at("02:00")),
            // The agent's own records carry the tool input and the reply text.
            codex("response_item", [
                "type": "function_call", "name": "shell",
                "arguments": "{\"command\":\"echo \(input)\"}",
            ], at: at("02:30")),
            codex("response_item", [
                "type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": "seen \(result) and \(reply)"]],
            ], at: at("03:00")),
            codex("event_msg", ["type": "task_complete"], at: at("04:00")),
        ]
    }

    @Test func waitSentinelsNeverLeak() async throws {
        let root = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        // Directory and file names carry sentinels too: a path must not reach
        // the output any more than prompt text may.
        let claudeRoot = root.appendingPathComponent("claude-\(path)/projects")
        let codexRoot = root.appendingPathComponent("codex-\(path)/sessions")
        let claudeFile = claudeRoot.appendingPathComponent("-work-\(path)/\(sessionID).jsonl")
        let codexFile = codexRoot
            .appendingPathComponent("2026/11/10/rollout-2026-11-10T08-00-00-\(sessionID).jsonl")
        try write(claudeTranscript(), to: claudeFile)
        try write(codexTranscript(), to: codexFile)

        let window = WaitWindow(lo: time("00:00") - 86_400_000, hi: time("59:00") + 86_400_000)
        let rows = await WaitIngest(adapters: [
            ClaudeCodeAdapter(projectsRoot: claudeRoot), CodexAdapter(sessionsRoot: codexRoot),
        ]).collect(since: window.lo)

        // Without this the rest proves nothing: the sentinel-bearing records had
        // to go through both extractors and produce a wait of every kind.
        let claude = try #require(rows.first { $0.agent == .claudeCode }?.fold)
        let codex = try #require(rows.first { $0.agent == .codex }?.fold)
        #expect(Set(claude.waits.map(\.kind)) == Set(WaitKind.allCases))
        #expect(codex.waits.contains { $0.kind == .turn })

        let text = WaitStats.format(rows, window: window)
        #expect(text.contains("sessions agent=claudeCode n=1"))
        #expect(text.contains("sessions agent=codex n=1"))
        #expect(text.contains("waits agent=claudeCode kind=turn n=1"))
        #expect(text.contains("waits agent=claudeCode kind=question answer=accept n=1"))
        #expect(text.contains("waits agent=claudeCode kind=approval answer=reject n=1"))
        #expect(text.contains("waits agent=codex kind=turn n=1"))

        var rendered = [text]
        for row in rows {
            rendered.append(String(describing: row.fold))
            rendered.append(String(reflecting: row.fold))
            for wait in row.fold.waits {
                rendered.append(String(describing: wait))
                rendered.append(String(reflecting: wait))
            }
        }
        #expect(rendered.count > 2)

        for rendered in rendered {
            for sentinel in sentinels() where rendered.contains(sentinel) {
                Issue.record("leaked \(sentinel) in: \(rendered)")
            }
        }

        // The transcripts on disk do hold the sentinels: the canary reads
        // synthetic data, and a typo in a name would leave it vacuous.
        let onDisk = try String(contentsOf: claudeFile, encoding: .utf8)
        #expect(onDisk.contains(prompt) && onDisk.contains(cwd) && onDisk.contains(sessionID))
    }
}
