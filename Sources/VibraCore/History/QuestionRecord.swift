import Foundation

/// One question the user typed into an agent.
///
/// Built only when the user opens the History window, held in memory while it
/// is open, and never written anywhere. Nothing that prints diagnostics or
/// machine-readable output may include `text`.
public struct QuestionRecord: Sendable, Equatable {
    public let agent: AgentKind
    public let sessionID: String
    public let timestamp: Date
    public let cwd: String
    public let text: String

    public init(agent: AgentKind, sessionID: String, timestamp: Date, cwd: String, text: String) {
        self.agent = agent
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.cwd = cwd
        self.text = text
    }

    public var project: String {
        cwd.isEmpty ? "(no folder)" : URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// The first non-empty line, at most `limit` characters: what a row shows.
    public func firstLine(limit: Int = 160) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// Longest text kept in memory per question.
    public static let maxLength = 2_000

    /// Trimmed and capped, or nil when nothing is left.
    public static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed.count > maxLength ? String(trimmed.prefix(maxLength)) : trimmed
    }
}

/// Pulls questions out of one JSONL source, fed every batch of that source in
/// order.
///
/// Stateful per source on purpose: whether a session is unattended is decided
/// by its first records (Codex's `session_meta.originator`, Claude's first
/// prompt), and a transcript longer than one read batch must still apply that
/// to every later batch. It carries only such session-level facts, never
/// earlier message text.
public protocol HistoryExtractor {
    mutating func fold(_ lines: [String]) -> [QuestionRecord]
}

/// A text block that is nothing but one wrapper element the agent injected —
/// `<environment_context>…</environment_context>` and the like — rather than
/// something the user typed.
func isInjectedWrapper(_ text: String, tags: Set<String>) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("<"),
          let close = trimmed.firstIndex(of: ">") else { return false }
    let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        .split(separator: " ").first.map(String.init) ?? ""
    return tags.contains(name) && trimmed.hasSuffix("</\(name)>")
}

/// Removes every injected wrapper element from `text`, returning what the user
/// actually typed (possibly empty).
func strippingWrappers(_ text: String, tags: Set<String>) -> String {
    var result = text
    for tag in tags {
        let pattern = "<\(NSRegularExpression.escapedPattern(for: tag))(\\s[^>]*)?>[\\s\\S]*?</\(NSRegularExpression.escapedPattern(for: tag))>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        result = regex.stringByReplacingMatches(
            in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Keeps pasted text but drops its `<pasted_content …>` markers.
func unwrappingPastes(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"</?pasted_content[^>]*>"#) else { return text }
    return regex.stringByReplacingMatches(
        in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
    ).trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Claude Code

/// Claude Code: `type: "user"` records that a person typed.
///
/// Excluded: `isMeta` (injected), `isSidechain` (a subagent's prompt), tool
/// results, command/stdout wrappers, interruption markers, and every question
/// in an unattended session (`entrypoint` "sdk-cli", or a scheduled task).
///
/// The wrapper tags are the leading tags observed in real user records on
/// 2026-09-26 (tag names counted, text not read): background-task
/// notifications and `!` shell runs arrive as user records without `isMeta`.
/// `pasted_content` is text the user pasted, so it is kept, unwrapped.
struct ClaudeHistoryExtractor: HistoryExtractor {
    static let wrapperTags: Set<String> = [
        "command-name", "command-message", "command-args",
        "local-command-stdout", "local-command-stderr", "local-command-caveat",
        "system-reminder", "task-notification",
        "bash-input", "bash-stdout", "bash-stderr",
    ]

    private var sawFirstPrompt = false
    private var scheduled = false
    private var sessionID: String?
    private var cwd: String?
    /// First seen wins, as in `ClaudeCheckpoint`, so a record that omits it
    /// is still judged by the session's entrypoint.
    private var entrypoint: String?

    mutating func fold(_ lines: [String]) -> [QuestionRecord] {
        var out: [QuestionRecord] = []
        for line in lines {
            guard let record = jsonObject(line) else { continue }
            if sessionID == nil { sessionID = record["sessionId"] as? String }
            if cwd == nil { cwd = record["cwd"] as? String }
            if entrypoint == nil { entrypoint = record["entrypoint"] as? String }
            guard record["type"] as? String == "user",
                  let message = record["message"] as? [String: Any]
            else { continue }

            if !sawFirstPrompt, let content = message["content"] as? String {
                sawFirstPrompt = true
                scheduled = scheduledTaskName(in: content) != nil
            }
            if scheduled || entrypoint == "sdk-cli" { continue }
            if record["isMeta"] as? Bool == true || record["isSidechain"] as? Bool == true { continue }

            let raw: String?
            switch message["content"] {
            case let text as String:
                raw = text
            case let blocks as [[String: Any]]:
                // A tool result is the agent talking to itself, not a question.
                guard !blocks.contains(where: { $0["type"] as? String == "tool_result" }) else { continue }
                raw = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: "\n")
            default:
                raw = nil
            }
            guard let raw else { continue }
            let typed = unwrappingPastes(strippingWrappers(raw, tags: Self.wrapperTags))
            if typed.hasPrefix("[Request interrupted by user") { continue }
            guard let text = QuestionRecord.normalized(typed),
                  let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            else { continue }
            out.append(QuestionRecord(
                agent: .claudeCode,
                sessionID: (record["sessionId"] as? String) ?? sessionID ?? "",
                timestamp: stamp,
                cwd: (record["cwd"] as? String) ?? cwd ?? "",
                text: text
            ))
        }
        return out
    }
}

// MARK: - Codex

/// Codex: `response_item` user messages' `input_text` blocks, minus the
/// context blocks Codex injects. `event_msg` `user_message` is ignored, so a
/// prompt is never counted twice by a version that writes both. A `codex exec`
/// session (originator "codex_exec") is unattended and yields nothing.
struct CodexHistoryExtractor: HistoryExtractor {
    /// `environment_context` and `turn_aborted` were observed; the other two
    /// are defensive.
    static let wrapperTags: Set<String> = ["environment_context", "turn_aborted", "user_instructions"]

    private var originator: String?
    private var sessionID: String?
    private var cwd: String?

    mutating func fold(_ lines: [String]) -> [QuestionRecord] {
        var out: [QuestionRecord] = []
        for line in lines {
            guard let record = jsonObject(line),
                  let payload = record["payload"] as? [String: Any]
            else { continue }
            let type = record["type"] as? String
            if type == "session_meta" {
                if originator == nil { originator = payload["originator"] as? String }
                if sessionID == nil { sessionID = payload["session_id"] as? String ?? payload["id"] as? String }
                if cwd == nil { cwd = payload["cwd"] as? String }
                continue
            }
            if type == "turn_context", cwd == nil { cwd = payload["cwd"] as? String }
            guard type == "response_item",
                  payload["type"] as? String == "message",
                  payload["role"] as? String == "user",
                  originator != "codex_exec",
                  let blocks = payload["content"] as? [[String: Any]]
            else { continue }

            let typed = blocks
                .compactMap { $0["type"] as? String == "input_text" ? $0["text"] as? String : nil }
                .filter { block in
                    !isInjectedWrapper(block, tags: Self.wrapperTags)
                        && !block.trimmingCharacters(in: .whitespaces).hasPrefix("# AGENTS.md instructions")
                }
                .joined(separator: "\n")
            guard let text = QuestionRecord.normalized(typed),
                  let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            else { continue }
            out.append(QuestionRecord(
                agent: .codex, sessionID: sessionID ?? "", timestamp: stamp, cwd: cwd ?? "", text: text))
        }
        return out
    }
}
