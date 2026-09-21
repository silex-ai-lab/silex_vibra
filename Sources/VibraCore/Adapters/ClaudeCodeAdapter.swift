import Foundation

/// Reads Claude Code sessions from `~/.claude/projects/<slug>/<uuid>.jsonl`.
///
/// Every line in a session file is a JSON record. `assistant` records carry the
/// model and per-response token usage; usage is summed across all assistant
/// records in the file so the session reflects the whole conversation, not one
/// API response. The oldest timestamp becomes `startedAt`, the newest becomes
/// `lastActivity`.
///
/// Steady-state polling goes through `sources()` + `update(...)`: the ingest
/// layer hands over only the records appended since the last poll, and the
/// checkpoint folds them into a running summary. The full-parse path reuses the
/// same folding logic, so the two paths are identical by construction.
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

    // MARK: - Incremental ingest

    public func sources() throws -> [SourceDescriptor] {
        let files: [URL]
        if let file {
            files = [file]
        } else if let projectsRoot {
            files = try jsonlFiles(under: projectsRoot)
        } else {
            files = []
        }
        // Stat only - never open or read a file here.
        return files.compactMap { SourceDescriptor.describing($0) }
    }

    public func update(
        source: SourceDescriptor,
        input: SourceInput,
        previous: ParsedState?
    ) throws -> ParsedState {
        guard case .records(let lines, let reset) = input else {
            // Not a JSONL source. Fall back to a full parse.
            return ParsedState(sessions: try discoverSessions(), checkpoint: nil)
        }

        var checkpoint: ClaudeCheckpoint
        if reset {
            checkpoint = ClaudeCheckpoint()
        } else if let previous, let carried = previous.checkpoint as? ClaudeCheckpoint {
            checkpoint = carried
        } else {
            checkpoint = ClaudeCheckpoint()
        }

        for line in lines {
            checkpoint.fold(line)
        }

        let session = checkpoint.buildSession(
            agent: kind,
            fallbackID: source.url.deletingPathExtension().lastPathComponent,
            fallbackDate: source.modified
        )
        return ParsedState(sessions: session.map { [$0] } ?? [], checkpoint: checkpoint)
    }

    // MARK: - Reporting

    /// One timestamped sample per `assistant` record. Each record's
    /// `message.usage` is a per-response delta, so the samples are additive and
    /// their sum equals the aggregate usage from `discoverSessions`. Timestamps
    /// are emitted as UTC `Date`s; `ReportBuilder` does local-day bucketing.
    public func usageSamples(from records: [String]) -> [UsageSample] {
        records.compactMap { line in
            guard let record = jsonObject(line) else { return nil }
            guard record["type"] as? String == "assistant" else { return nil }
            guard let message = record["message"] as? [String: Any] else { return nil }
            guard let u = message["usage"] as? [String: Any] else { return nil }

            let usage = TokenUsage(
                input: jsonInt(u["input_tokens"]),
                output: jsonInt(u["output_tokens"]),
                cacheCreation: jsonInt(u["cache_creation_input_tokens"]),
                cacheRead: jsonInt(u["cache_read_input_tokens"])
            )
            let timestamp = (record["timestamp"] as? String).flatMap(parseISODate)
            let model = message["model"] as? String
            return UsageSample(timestamp: timestamp, model: model, usage: usage)
        }
    }

    // MARK: - Full parse

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

    private func parseSession(at file: URL) -> Session? {
        let lines = readLines(file) ?? []
        var checkpoint = ClaudeCheckpoint()
        for line in lines {
            checkpoint.fold(line)
        }
        return checkpoint.buildSession(
            agent: kind,
            fallbackID: file.deletingPathExtension().lastPathComponent,
            fallbackDate: fileModificationDate(file) ?? Date()
        )
    }
}

// MARK: - Claude checkpoint

/// Per-file running summary for a Claude Code transcript. Folding is the same
/// code whether it runs over the whole file at once or over a trailing slice.
struct ClaudeCheckpoint: AdapterCheckpoint {
    var sessionID: String?
    var cwd: String?
    var gitBranch: String?
    var model: String?
    var usage = TokenUsage.zero
    var earliest: Date?
    var latest: Date?
    var lastRecordType: String?
    var lastAssistantStopReason: String?
    var scheduledTask: String?
    var sawFirstPrompt = false
    var parsedRecords = 0

    mutating func fold(_ line: String) {
        guard let record = jsonObject(line) else { return }
        parsedRecords += 1

        let type = record["type"] as? String
        if let type { lastRecordType = type }

        if let raw = record["timestamp"] as? String, let ts = parseISODate(raw) {
            if earliest == nil || ts < earliest! { earliest = ts }
            if latest == nil || ts > latest! { latest = ts }
        }

        if sessionID == nil { sessionID = (record["sessionId"] as? String) ?? (record["session_id"] as? String) }
        if cwd == nil { cwd = record["cwd"] as? String }
        if gitBranch == nil { gitBranch = record["gitBranch"] as? String }

        // Only the first typed prompt, and only the task's name from it: a
        // scheduled run opens with `<scheduled-task name="..." ...>`. The rest
        // of the prompt is conversation content and is never kept.
        if type == "user", !sawFirstPrompt,
           let message = record["message"] as? [String: Any],
           let content = message["content"] as? String {
            sawFirstPrompt = true
            scheduledTask = scheduledTaskName(in: content)
        }

        guard type == "assistant" else { return }
        guard let message = record["message"] as? [String: Any] else { return }

        if model == nil { model = message["model"] as? String }
        if let stopReason = message["stop_reason"] as? String { lastAssistantStopReason = stopReason }
        if let u = message["usage"] as? [String: Any] {
            // Claude usage is per-response: accumulate across every assistant
            // record, never replace.
            usage += TokenUsage(
                input: jsonInt(u["input_tokens"]),
                output: jsonInt(u["output_tokens"]),
                cacheCreation: jsonInt(u["cache_creation_input_tokens"]),
                cacheRead: jsonInt(u["cache_read_input_tokens"])
            )
        }
    }

    func buildSession(agent: AgentKind, fallbackID: String, fallbackDate: Date) -> Session? {
        // A file with nothing parseable in it is not a session.
        guard parsedRecords > 0 else { return nil }

        let sessionID = sessionID ?? fallbackID
        let started = earliest ?? fallbackDate
        let last = latest ?? started

        // A trailing permission-mode record means the agent is parked on an
        // approval prompt; otherwise the last assistant stop_reason decides.
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
            agent: agent,
            cwd: cwd ?? "",
            gitBranch: gitBranch,
            model: model,
            state: .idle,
            startedAt: started,
            lastActivity: last,
            usage: usage,
            lastEvent: lastEvent,
            scheduledTask: scheduledTask
        )
    }
}

/// The name from a leading `<scheduled-task name="...">` tag, or nil. Anchored
/// at the start and restricted to a short slug, so arbitrary prompt text that
/// merely mentions the tag can never become a notification key or label.
func scheduledTaskName(in prompt: String) -> String? {
    let pattern = #"^\s*<scheduled-task name="([A-Za-z0-9._-]{1,64})""#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
              in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
          let range = Range(match.range(at: 1), in: prompt)
    else { return nil }
    return String(prompt[range])
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

/// Streams complete lines out of a file in bounded memory. The previous
/// whole-file string load was what ballooned resident size to 626 MB on a
/// 262 MB transcript tree.
func readLines(_ url: URL) -> [String]? {
    guard let result = try? IncrementalLineReader().read(url: url, from: 0) else { return nil }
    return result.lines
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
