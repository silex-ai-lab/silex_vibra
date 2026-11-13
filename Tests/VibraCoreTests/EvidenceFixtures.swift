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
        _ id: String, name: String = "Bash", input: [String: Any], cwd: String? = nil,
        at seconds: TimeInterval
    ) -> String {
        var record: [String: Any] = [
            "type": "assistant", "timestamp": stamp(seconds),
            "message": ["role": "assistant", "content": [
                ["type": "tool_use", "id": id, "name": name, "input": input] as [String: Any],
            ]] as [String: Any],
        ]
        if let cwd { record["cwd"] = cwd }
        return json(record)
    }

    static func claudeBash(_ id: String, _ command: String, at seconds: TimeInterval) -> String {
        claudeUse(id, input: ["command": command], at: seconds)
    }

    static func claudeEdit(
        _ id: String, path: String = "/work/App.swift", name: String = "Edit",
        old: String? = nil, new: String? = nil, replaceAll: Bool = false, cwd: String? = nil,
        at seconds: TimeInterval
    ) -> String {
        var input: [String: Any] = ["file_path": path]
        if let old { input["old_string"] = old }
        if let new { input["new_string"] = new }
        if replaceAll { input["replace_all"] = true }
        return claudeUse(id, name: name, input: input, cwd: cwd, at: seconds)
    }

    static func claudeNotebookEdit(
        _ id: String, path: String, cwd: String? = nil, at seconds: TimeInterval
    ) -> String {
        claudeUse(id, name: "NotebookEdit", input: ["notebook_path": path], cwd: cwd, at: seconds)
    }

    static func claudeMultiEdit(
        _ id: String, path: String, edits: [(old: String, new: String)], replaceAll: Bool = false,
        cwd: String? = nil, at seconds: TimeInterval
    ) -> String {
        let entries: [[String: Any]] = edits.map {
            var entry: [String: Any] = ["old_string": $0.old, "new_string": $0.new]
            if replaceAll { entry["replace_all"] = true }
            return entry
        }
        return claudeUse(id, name: "MultiEdit", input: ["file_path": path, "edits": entries], cwd: cwd, at: seconds)
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
            "status": exit == nil || exit == 0 ? "completed" : "failed",
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

    /// Codex names the workspace root in these two record types only.
    static func codexMeta(cwd: String, at seconds: TimeInterval) -> String {
        json([
            "type": "session_meta", "timestamp": stamp(seconds),
            "payload": ["session_id": "s", "id": "s", "cwd": cwd],
        ])
    }

    static func codexTurnContext(cwd: String, at seconds: TimeInterval) -> String {
        json(["type": "turn_context", "timestamp": stamp(seconds), "payload": ["cwd": cwd]])
    }
}

// MARK: Issue-time views
//
// Most tests are about issue order. They build events without completion
// times and compare extractor output with those times dropped; completion
// times have their own tests.

extension ObservedCheck {
    init(at: Date, kind: CheckKind, result: CheckResult) {
        self.init(at: at, completedAt: nil, kind: kind, result: result)
    }

    var issueOnly: ObservedCheck { ObservedCheck(at: at, completedAt: nil, kind: kind, result: result) }
}

extension EvidenceEvent {
    static func codeChange(at date: Date) -> EvidenceEvent {
        .codeChange(CodeChange(at: date, completedAt: nil, target: .source))
    }

    var issueOnly: EvidenceEvent {
        switch self {
        case .check(let check): .check(check.issueOnly)
        case .codeChange(let change): .codeChange(CodeChange(at: change.at, completedAt: nil, target: change.target))
        }
    }
}

extension EvidenceFold {
    var issueOnly: EvidenceFold { EvidenceFold(events: events.map(\.issueOnly), sawToolRecords: sawToolRecords) }
}

extension DeliveryEvidence {
    static func checkedAfterLastChange(_ check: ObservedCheck) -> DeliveryEvidence {
        .checkedAfterLastChange(check, testEdits: [])
    }

    var issueOnly: DeliveryEvidence {
        switch self {
        case .changedAfterLastCheck(let change, let check): .changedAfterLastCheck(lastChange: change, check: check.issueOnly)
        case .checkedAfterLastChange(let check, let edits): .checkedAfterLastChange(check.issueOnly, testEdits: edits)
        default: self
        }
    }
}
