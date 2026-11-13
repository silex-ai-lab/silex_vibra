import Foundation

/// Reads Claude Code sessions from `~/.claude/projects/<slug>/<uuid>.jsonl`.
///
/// Every line in a session file is a JSON record. `assistant` records carry the
/// model and per-response token usage; `ClaudeUsageSampler` folds the records
/// of one response into one usage, and those are summed across the file so the
/// session reflects the whole conversation, not one API response. The oldest
/// timestamp becomes `startedAt`, the newest becomes `lastActivity`.
///
/// Steady-state polling goes through `sources()` + `update(...)`: the ingest
/// layer hands over only the records appended since the last poll, and the
/// checkpoint folds them into a running summary. The full-parse path reuses the
/// same folding logic, so the two paths are identical by construction.
public struct ClaudeCodeAdapter: AgentAdapter {
    public let kind: AgentKind = .claudeCode

    private let projectsRoot: URL?
    private let file: URL?
    /// Keeps the per-directory listing between refreshes.
    private let scanner = JSONLTreeScanner()

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
            files = try scanner.files(under: projectsRoot)
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

        // A subagent transcript carries its parent's session id. It still counts
        // for usage, but it is not a session anyone can return to.
        let session = isSubagentSource(source.url) ? nil : checkpoint.buildSession(
            agent: kind,
            fallbackID: source.url.deletingPathExtension().lastPathComponent,
            fallbackDate: source.modified
        )
        return ParsedState(sessions: session.map { [$0] } ?? [], checkpoint: checkpoint)
    }

    // MARK: - Reporting

    /// One sample per API response, folded from the records that share its
    /// `message.id`, so the samples are additive and their sum equals the
    /// usage from `discoverSessions`. Timestamps are emitted as UTC `Date`s;
    /// `ReportBuilder` does local-day bucketing.
    public func makeUsageSampler(for source: URL) -> any UsageSampler {
        ClaudeUsageSampler(isSubagent: isSubagentSource(source))
    }

    /// A directory named `subagents` between the projects root and the file.
    /// The single-file entry point has no root, so it is never a subagent.
    private func isSubagentSource(_ url: URL) -> Bool {
        guard let projectsRoot else { return false }
        let root = projectsRoot.standardizedFileURL.pathComponents
        let path = url.standardizedFileURL.pathComponents
        guard path.count > root.count, path[..<root.count].elementsEqual(root) else { return false }
        return path[root.count..<(path.count - 1)].contains("subagents")
    }

    // MARK: - History

    public func historyExtractor() -> (any HistoryExtractor)? { ClaudeHistoryExtractor() }
    public func waitExtractor() -> (any WaitExtractor)? { ClaudeWaitExtractor() }

    // MARK: - Evidence

    public func evidenceExtractor() -> (any EvidenceExtractor)? { ClaudeEvidenceExtractor() }

    // MARK: - Incidents

    public func incidentExtractor() -> (any IncidentExtractor)? { ClaudeIncidentExtractor() }

    /// `<id>.jsonl` and `<id>/subagents/*.jsonl` beside it.
    public func evidenceSources(for session: Session) -> [URL] {
        if let file { return [file] }
        guard let projectsRoot, let files = try? scanner.files(under: projectsRoot) else { return [] }
        return files.filter { url in
            if url.lastPathComponent == "\(session.id).jsonl" { return !isSubagentSource(url) }
            let parts = url.standardizedFileURL.pathComponents
            return parts.count >= 3 && parts[parts.count - 2] == "subagents" && parts[parts.count - 3] == session.id
        }
    }

    // MARK: - Full parse

    public func discoverSessions() throws -> [Session] {
        let files: [URL]
        if let file {
            files = [file]
        } else if let projectsRoot {
            files = try jsonlFiles(under: projectsRoot).filter { !isSubagentSource($0) }
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
        var checkpoint = ClaudeCheckpoint()
        foldLineBatches(of: file) { lines in
            for line in lines {
                checkpoint.fold(line)
            }
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
    /// Usage of every response the sampler has made final. The session's
    /// usage is this plus the response still pending in the sampler, so a
    /// response split across two reads or two polls is counted once.
    var committed = TokenUsage.zero
    var sampler = ClaudeUsageSampler()
    var earliest: Date?
    var latest: Date?
    var lastRecordType: String?
    var lastAssistantStopReason: String?
    var scheduledTask: String?
    var entrypoint: String?
    var sawFirstPrompt = false
    /// The latest typed prompt came from a fleet planner, not a human.
    var lastPromptIsDispatch = false
    var parsedRecords = 0

    mutating func fold(_ line: String) {
        guard let record = jsonObject(line) else { return }
        parsedRecords += 1

        let type = record["type"] as? String
        if let type { lastRecordType = type }

        let timestamp = (record["timestamp"] as? String).flatMap(parseISODate)
        if let ts = timestamp {
            if earliest == nil || ts < earliest! { earliest = ts }
            if latest == nil || ts > latest! { latest = ts }
        }

        if sessionID == nil { sessionID = (record["sessionId"] as? String) ?? (record["session_id"] as? String) }
        if cwd == nil { cwd = record["cwd"] as? String }
        if gitBranch == nil { gitBranch = record["gitBranch"] as? String }
        if entrypoint == nil { entrypoint = record["entrypoint"] as? String }

        // Only the first typed prompt, and only the task's name from it: a
        // scheduled run opens with `<scheduled-task name="..." ...>`. The rest
        // of the prompt is conversation content and is never kept.
        if type == "user", !sawFirstPrompt,
           let message = record["message"] as? [String: Any],
           let content = message["content"] as? String {
            sawFirstPrompt = true
            scheduledTask = scheduledTaskName(in: content)
        }

        if type == "user",
           let message = record["message"] as? [String: Any],
           let content = message["content"] as? String {
            lastPromptIsDispatch = isFleetDispatch(content)
        }

        guard type == "assistant" else { return }
        guard let message = record["message"] as? [String: Any] else { return }

        if model == nil { model = message["model"] as? String }
        if let stopReason = message["stop_reason"] as? String { lastAssistantStopReason = stopReason }
        for sample in sampler.add(record: record, timestamp: timestamp, detail: false) {
            committed += sample.usage
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
            case "end_turn": lastEvent = lastPromptIsDispatch ? .settled : .turnComplete
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
            usage: committed + sampler.pendingUsage,
            lastEvent: lastEvent,
            scheduledTask: scheduledTask,
            entrypoint: entrypoint
        )
    }
}

// MARK: - Claude usage sampler

/// Folds the records of one API response into one sample.
///
/// Claude Code writes a response as several `assistant` records, one per
/// content block, each repeating `message.id` and the response's `usage`.
/// Summing them counted a response once per block, which about doubled the
/// Usage Report's Claude Code total on this machine (measured ratio 2.13).
/// Records that share an ID merge
/// into one pending sample; the last record's usage is the response's usage,
/// since only `output_tokens` grows between them. A record with another ID,
/// or none, makes the pending sample final. Records with no ID never merge.
struct ClaudeUsageSampler: UsageSampler {
    let isSubagent: Bool
    /// The response whose records may still be arriving. Only a record with
    /// an ID can be pending; one without is final the moment it is read.
    private var pending: (id: String, sample: UsageSample)?

    init(isSubagent: Bool = false) {
        self.isSubagent = isSubagent
    }

    var pendingUsage: TokenUsage { pending?.sample.usage ?? .zero }

    mutating func add(_ lines: [String]) -> [UsageSample] {
        var final: [UsageSample] = []
        for line in lines {
            // Date parsing builds formatters and dominated a 7-day report at
            // 2.6x the old cost, so only records the fold can use pay for it.
            guard let record = jsonObject(line),
                  record["type"] as? String == "assistant",
                  (record["message"] as? [String: Any])?["usage"] is [String: Any]
            else { continue }
            let timestamp = (record["timestamp"] as? String).flatMap(parseISODate)
            final += add(record: record, timestamp: timestamp, detail: true)
        }
        return final
    }

    /// The fold. `detail: false` skips tool names and project, which the live
    /// path never shows; the rules are otherwise the same for both callers.
    mutating func add(record: [String: Any], timestamp: Date?, detail: Bool) -> [UsageSample] {
        guard record["type"] as? String == "assistant",
              let message = record["message"] as? [String: Any],
              let u = message["usage"] as? [String: Any]
        else { return [] }

        let sample = UsageSample(
            timestamp: timestamp,
            model: message["model"] as? String,
            usage: TokenUsage(
                input: jsonInt(u["input_tokens"]),
                output: jsonInt(u["output_tokens"]),
                cacheCreation: jsonInt(u["cache_creation_input_tokens"]),
                cacheRead: jsonInt(u["cache_read_input_tokens"])
            ),
            toolNames: detail ? Self.toolNames(in: message) : [],
            project: detail ? Self.projectName(ofCWD: record["cwd"] as? String) : nil,
            isSidechain: record["isSidechain"] as? Bool == true
        )
        let id = message["id"] as? String

        if let id, let held = pending, held.id == id {
            pending = (id, UsageSample(
                timestamp: held.sample.timestamp ?? sample.timestamp,
                model: sample.model ?? held.sample.model,
                usage: sample.usage,
                toolNames: held.sample.toolNames + sample.toolNames,
                project: sample.project ?? held.sample.project,
                isSidechain: held.sample.isSidechain || sample.isSidechain
            ))
            return []
        }

        var final = finish()
        if let id {
            pending = (id, sample)
        } else {
            final.append(sample)
        }
        return final
    }

    mutating func finish() -> [UsageSample] {
        defer { pending = nil }
        return pending.map { [$0.sample] } ?? []
    }

    /// `tool_use.name` values, in order. Never the block's `input`.
    private static func toolNames(in message: [String: Any]) -> [String] {
        guard let content = message["content"] as? [Any] else { return [] }
        return content.compactMap { block in
            guard let block = block as? [String: Any],
                  block["type"] as? String == "tool_use",
                  let name = block["name"] as? String, !name.isEmpty
            else { return nil }
            return name
        }
    }

    /// Last non-empty path component, so no parent directory leaves the file.
    private static func projectName(ofCWD cwd: String?) -> String? {
        cwd?.split(separator: "/").last.map(String.init)
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

/// Hands every complete line of a file to `fold`, one bounded batch at a time,
/// and returns the bytes read. The previous whole-file string load was what
/// ballooned resident size to 626 MB on a 262 MB transcript tree, and a single
/// `read` stops at `maxLinesPerRead`, which silently cut long transcripts at
/// 2,000 lines.
@discardableResult
func foldLineBatches(
    of url: URL,
    reader: IncrementalLineReader = IncrementalLineReader(),
    _ fold: ([String]) -> Void
) -> Int {
    var offset: UInt64 = 0
    var bytesRead = 0
    while true {
        guard let batch = try? reader.read(url: url, from: offset) else { break }
        bytesRead += batch.bytesRead
        let advanced = batch.nextOffset > offset
        offset = batch.nextOffset
        if batch.lines.isEmpty && !advanced { break }
        // Drain per batch: JSONSerialization autoreleases, and a
        // multi-hundred-megabyte pass without this was worth hundreds of
        // megabytes of resident memory.
        autoreleasepool { fold(batch.lines) }
        if !advanced { break }
    }
    return bytesRead
}

func fileModificationDate(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

func jsonlFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        // Nil means the root could not be enumerated. A root that is gone is
        // not an error; one that is still there is.
        var info = stat()
        guard lstat(root.path, &info) != 0 || info.st_mode & S_IFMT != S_IFDIR else {
            throw SourceListError()
        }
        return []
    }
    var files: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        files.append(url)
    }
    return files
}
