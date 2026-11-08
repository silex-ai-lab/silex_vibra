import Foundation
@testable import VibraCore

/// Builders for transcript lines. Fixtures only: no test reads a real transcript.
enum EvidenceFixtures {
    static let base = ISO8601DateFormatter().date(from: "2026-11-08T10:00:00Z")!

    static func stamp(_ seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: base.addingTimeInterval(seconds))
    }

    static func at(_ seconds: TimeInterval) -> Date {
        parseISODate(stamp(seconds)) ?? base
    }

    static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    // MARK: Claude Code

    static func claudeUse(
        _ id: String, name: String = "Bash", input: [String: Any], at seconds: TimeInterval
    ) -> String {
        json([
            "type": "assistant", "timestamp": stamp(seconds),
            "message": ["role": "assistant", "content": [
                ["type": "tool_use", "id": id, "name": name, "input": input] as [String: Any],
            ]] as [String: Any],
        ])
    }

    static func claudeBash(_ id: String, _ command: String, at seconds: TimeInterval) -> String {
        claudeUse(id, input: ["command": command], at: seconds)
    }

    static func claudeEdit(_ id: String, path: String = "/work/App.swift", name: String = "Edit", at seconds: TimeInterval) -> String {
        claudeUse(id, name: name, input: ["file_path": path], at: seconds)
    }

    static func claudeResult(
        _ id: String, text: String, isError: Bool = false, asBlocks: Bool = false, at seconds: TimeInterval
    ) -> String {
        let content: Any = asBlocks ? [["type": "text", "text": text]] : text
        return json([
            "type": "user", "timestamp": stamp(seconds),
            "message": ["role": "user", "content": [
                ["type": "tool_result", "tool_use_id": id, "content": content, "is_error": isError] as [String: Any],
            ]] as [String: Any],
        ])
    }

    // MARK: Codex

    static func codexCommand(
        _ script: String, exit: Int?, output: String = "", durationSeconds: Int = 0, at seconds: TimeInterval
    ) -> String {
        var item: [String: Any] = [
            "type": "CommandExecution", "command": ["zsh", "-lc", script],
            "aggregated_output": output, "duration": ["secs": durationSeconds, "nanos": 0],
        ]
        if let exit { item["exit_code"] = exit }
        return codexItem(item, at: seconds)
    }

    static func codexChange(_ paths: [String], status: String = "completed", at seconds: TimeInterval) -> String {
        var changes: [String: Any] = [:]
        for path in paths { changes[path] = ["type": "update"] }
        return codexItem(["type": "FileChange", "changes": changes, "status": status], at: seconds)
    }

    static func codexItem(_ item: [String: Any], at seconds: TimeInterval) -> String {
        json([
            "type": "event_msg", "timestamp": stamp(seconds),
            "payload": ["type": "item_completed", "item": item] as [String: Any],
        ])
    }
}
