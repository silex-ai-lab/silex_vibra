import Foundation

/// Reads Claude Code sessions from `~/.claude/projects/<slug>/<uuid>.jsonl`.
///
/// Every line in a session file is a JSON record. `assistant` records carry the
/// model and per-response token usage; usage is summed across all assistant
/// records in the file so the session reflects the whole conversation, not one
/// API response. The oldest timestamp becomes `startedAt`, the newest becomes
/// `lastActivity`.
public struct ClaudeCodeAdapter: AgentAdapter {
    public let kind: AgentKind = .claudeCode

    private let projectsRoot: URL?
    private let file: URL?

    /// Production entry point: read the whole projects tree.
    public init(projectsRoot: URL = VibraPaths.claudeProjects) {
        self.projectsRoot = projectsRoot
        self.file = nil
    }

    /// Test/fixture entry point: read exactly one `.jsonl` file.
    public init(file: URL) {
        self.projectsRoot = nil
        self.file = file
    }

    public var isAvailable: Bool {
        if let file {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) && !isDir.boolValue
        }
        guard let projectsRoot else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: projectsRoot.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func discoverSessions() throws -> [Session] {
        let files: [URL]
        if let file {
            files = [file]
        } else if let projectsRoot {
            files = try jsonlFiles(under: projectsRoot)
        } else {
            files = []
        }

        var sessions: [Session] = []
        for file in files {
            if let session = parseSession(at: file) {
                sessions.append(session)
            }
        }
        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Parsing

    private func parseSession(at file: URL) -> Session? {
        guard let lines = readLines(file) else { return nil }

        var id: String?
        var cwd: String?
        var gitBranch: String?
        var model: String?
        var usage = TokenUsage.zero
        var oldest: Date?
        var newest: Date?
        var lastRecordType: String?
        var lastAssistantStopReason: String?
        var parsedRecords = 0

        for line in lines {
            guard let record = jsonObject(line) else { continue }
            parsedRecords += 1

            let type = record["type"] as? String
            if let type { lastRecordType = type }

            if let raw = record["timestamp"] as? String, let ts = parseISODate(raw) {
                if oldest == nil || ts < oldest! { oldest = ts }
                if newest == nil || ts > newest! { newest = ts }
            }

            if id == nil { id = (record["sessionId"] as? String) ?? (record["session_id"] as? String) }
            if cwd == nil { cwd = record["cwd"] as? String }
            if gitBranch == nil { gitBranch = record["gitBranch"] as? String }

            guard type == "assistant" else { continue }
            guard let message = record["message"] as? [String: Any] else { continue }

            if model == nil { model = message["model"] as? String }
            if let stopReason = message["stop_reason"] as? String { lastAssistantStopReason = stopReason }
            if let u = message["usage"] as? [String: Any] {
                usage += TokenUsage(
                    input: jsonInt(u["input_tokens"]),
                    output: jsonInt(u["output_tokens"]),
                    cacheCreation: jsonInt(u["cache_creation_input_tokens"]),
                    cacheRead: jsonInt(u["cache_read_input_tokens"])
                )
            }
        }

        // A file with nothing parseable in it is not a session. Without this,
        // an empty or corrupt .jsonl yields a phantom row: no tokens, no model,
        // and a project name derived from the process's current directory
        // rather than the session's. Observed during robustness testing.
        guard parsedRecords > 0 else { return nil }

        let sessionID = id ?? file.deletingPathExtension().lastPathComponent
        let started = oldest ?? fileModificationDate(file) ?? Date()
        let last = newest ?? started

        // A trailing permission-mode record means the agent is parked on an
        // approval prompt; otherwise the last assistant stop_reason decides
        // whether it is still producing or has handed the turn back.
        let lastEvent: LastEventKind
        if lastRecordType == "permission-mode" {
            lastEvent = .permissionPrompt
        } else {
            switch lastAssistantStopReason {
            case "tool_use": lastEvent = .producing
            case "end_turn": lastEvent = .turnComplete
            default: lastEvent = .unknown
            }
        }

        return Session(
            id: sessionID,
            agent: kind,
            cwd: cwd ?? "",
            gitBranch: gitBranch,
            model: model,
            state: .idle,
            startedAt: started,
            lastActivity: last,
            usage: usage,
            lastEvent: lastEvent
        )
    }
}

// MARK: - Shared JSONL helpers
//
// These are used by both the Claude Code and Codex adapters. They live here
// (rather than in a separate file) to keep the file-ownership boundary intact.

func parseISODate(_ string: String) -> Date? {
    let options: [ISO8601DateFormatter.Options] = [
        [.withInternetDateTime, .withFractionalSeconds],
        [.withInternetDateTime],
    ]
    for option in options {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = option
        if let date = formatter.date(from: string) { return date }
    }
    return nil
}

func jsonObject(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func jsonInt(_ value: Any?) -> Int {
    switch value {
    case let n as Int: return n
    case let n as Int64: return Int(n)
    case let n as NSNumber: return n.intValue
    case let s as String: return Int(s) ?? 0
    default: return 0
    }
}

func readLines(_ url: URL) -> [String]? {
    guard let data = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    return data.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

func fileModificationDate(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

func jsonlFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return []
    }
    var files: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        files.append(url)
    }
    return files
}
