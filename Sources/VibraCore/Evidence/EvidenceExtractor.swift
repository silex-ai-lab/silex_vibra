import Foundation

public struct EvidenceFold: Sendable, Equatable {
    public var events: [EvidenceEvent]
    public var sawToolRecords: Bool

    public init(events: [EvidenceEvent] = [], sawToolRecords: Bool = false) {
        self.events = events
        self.sawToolRecords = sawToolRecords
    }
}

/// Reduces one transcript to change and check events, fed every batch of that
/// transcript in order.
///
/// Command text, file paths and tool output are read, mapped to enums and a
/// date, and dropped inside `fold`. Nothing an extractor keeps or returns may
/// carry any of them.
public protocol EvidenceExtractor {
    mutating func fold(_ lines: [String])
    /// Settles calls that never got a result.
    mutating func finish() -> EvidenceFold
}

private let documentationExtensions: Set<String> = [
    "md", "mdx", "txt", "rst", "png", "jpg", "jpeg", "gif", "svg", "pdf",
]
private let scratchPrefixes = ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]

func isCodePath(_ path: String) -> Bool {
    if scratchPrefixes.contains(where: path.hasPrefix) { return false }
    return !documentationExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
}

/// A masked exit status says nothing about the check, so only the runner's own
/// summary can decide, and an undecided summary stays unknown.
func checkResult(exitVisible: Bool, exitCode: Int?, outputTail: String) -> CheckResult {
    if exitVisible, let exitCode { return exitCode == 0 ? .passed(.exitStatus) : .failed(.exitStatus) }
    switch RunnerSummary.verdict(outputTail: outputTail) {
    case true?: return .passed(.runnerSummary)
    case false?: return .failed(.runnerSummary)
    case nil: return .unknown
    }
}

// MARK: - Claude Code

/// Claude Code: a `tool_use` block in an assistant record, answered by a
/// `tool_result` block in a later user record, possibly in a later batch.
///
/// A call is classified when it opens, so only enums and a date wait for the
/// result. Ids repeat in transcripts, so each tracked id is opened once and a
/// replayed record cannot reopen a finished call.
struct ClaudeEvidenceExtractor: EvidenceExtractor {
    private enum Pending {
        case check(CheckKind, exitVisible: Bool, at: Date)
        case edit(at: Date)
    }

    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    private static let rejection = "The user doesn"

    private var pending: [String: Pending] = [:]
    private var tracked: Set<String> = []
    private var result = EvidenceFold()

    mutating func fold(_ lines: [String]) {
        for line in lines {
            let isUse = line.contains("\"tool_use\"")
            guard isUse || line.contains("\"tool_result\""),
                  let record = jsonObject(line),
                  let blocks = (record["message"] as? [String: Any])?["content"] as? [[String: Any]]
            else { continue }
            let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            for block in blocks {
                switch block["type"] as? String {
                case "tool_use": open(block, at: stamp)
                case "tool_result": close(block)
                default: continue
                }
            }
        }
    }

    private mutating func open(_ block: [String: Any], at stamp: Date?) {
        result.sawToolRecords = true
        guard let id = block["id"] as? String, let stamp, !tracked.contains(id),
              let name = block["name"] as? String,
              let input = block["input"] as? [String: Any]
        else { return }
        if name == "Bash" {
            guard let command = input["command"] as? String,
                  let found = CommandClassifier.classify(script: command) else { return }
            tracked.insert(id)
            pending[id] = .check(found.kind, exitVisible: found.exitVisible, at: stamp)
        } else if Self.editTools.contains(name) {
            guard let path = (input["file_path"] ?? input["notebook_path"]) as? String, isCodePath(path) else { return }
            tracked.insert(id)
            pending[id] = .edit(at: stamp)
        }
    }

    private mutating func close(_ block: [String: Any]) {
        guard let id = block["tool_use_id"] as? String, let call = pending.removeValue(forKey: id) else { return }
        let text = Self.text(of: block["content"])
        let rejected = text.hasPrefix(Self.rejection)
        let isError = block["is_error"] as? Bool ?? false
        switch call {
        case .edit(let at):
            if !isError && !rejected { result.events.append(.codeChange(at)) }
        case .check(let kind, let exitVisible, let at):
            let outcome: CheckResult = rejected
                ? .unknown
                : checkResult(exitVisible: exitVisible, exitCode: isError ? 1 : 0, outputTail: text)
            result.events.append(.check(ObservedCheck(at: at, kind: kind, result: outcome)))
        }
    }

    private static func text(of content: Any?) -> String {
        switch content {
        case let string as String: return string
        case let blocks as [[String: Any]]: return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        default: return ""
        }
    }

    mutating func finish() -> EvidenceFold {
        for case .check(let kind, _, let at) in pending.values {
            result.events.append(.check(ObservedCheck(at: at, kind: kind, result: .unknown)))
        }
        pending = [:]
        return result
    }
}

// MARK: - Codex

/// Codex: one `item_completed` event per finished command or file change.
/// A command carries its own exit code, duration and output, so no state
/// crosses a record.
struct CodexEvidenceExtractor: EvidenceExtractor {
    private var result = EvidenceFold()

    mutating func fold(_ lines: [String]) {
        for line in lines where line.contains("\"item_completed\"") {
            guard let record = jsonObject(line),
                  record["type"] as? String == "event_msg",
                  let payload = record["payload"] as? [String: Any],
                  payload["type"] as? String == "item_completed",
                  let item = payload["item"] as? [String: Any],
                  let stamp = (record["timestamp"] as? String).flatMap(parseISODate)
            else { continue }
            switch item["type"] as? String {
            case "CommandExecution": command(item, completedAt: stamp)
            case "FileChange": change(item, at: stamp)
            default: continue
            }
        }
    }

    private mutating func command(_ item: [String: Any], completedAt stamp: Date) {
        result.sawToolRecords = true
        guard let argv = item["command"] as? [String] else { return }
        let script = argv.count >= 3 && ["-lc", "-c"].contains(argv[1]) ? argv[2] : argv.joined(separator: " ")
        guard let found = CommandClassifier.classify(script: script) else { return }
        let duration = item["duration"] as? [String: Any]
        let seconds = Double(jsonInt(duration?["secs"])) + Double(jsonInt(duration?["nanos"])) / 1e9
        let outcome = checkResult(
            exitVisible: found.exitVisible,
            exitCode: (item["exit_code"] as? NSNumber)?.intValue,
            outputTail: item["aggregated_output"] as? String ?? "")
        result.events.append(.check(ObservedCheck(at: stamp.addingTimeInterval(-seconds), kind: found.kind, result: outcome)))
    }

    private mutating func change(_ item: [String: Any], at stamp: Date) {
        result.sawToolRecords = true
        guard item["status"] as? String == "completed",
              let changes = item["changes"] as? [String: Any],
              changes.keys.contains(where: isCodePath) else { return }
        result.events.append(.codeChange(stamp))
    }

    mutating func finish() -> EvidenceFold { result }
}
