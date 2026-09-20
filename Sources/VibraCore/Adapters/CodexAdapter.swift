import Foundation

/// Reads Codex sessions from `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// The `session_meta` record identifies the session (id, cwd, model) and the
/// `token_usage_record` records carry `thread_token_usage`, which is cumulative
/// across the thread. The last `thread_token_usage` seen therefore holds the
/// session total; summing `thread_token_usage` across records would multi-count.
///
/// Steady-state polling goes through `sources()` + `update(...)`. The cumulative
/// rule and the full-parse rule are the same code path, so a folded result is
/// byte-for-byte the same as a fresh parse.
public struct CodexAdapter: AgentAdapter {
    public let kind: AgentKind = .codex

    private let sessionsRoot: URL?
    private let file: URL?

    /// Production entry point: read the whole sessions tree.
    public init(sessionsRoot: URL = VibraPaths.codexSessions) {
        self.sessionsRoot = sessionsRoot
        self.file = nil
    }

    /// Test/fixture entry point: read exactly one `.jsonl` file.
    public init(file: URL) {
        self.sessionsRoot = nil
        self.file = file
    }

    public var isAvailable: Bool {
        if let file {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) && !isDir.boolValue
        }
        guard let sessionsRoot else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: sessionsRoot.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Incremental ingest

    public func sources() throws -> [SourceDescriptor] {
        let files: [URL]
        if let file {
            files = [file]
        } else if let sessionsRoot {
            files = try jsonlFiles(under: sessionsRoot)
                .filter { $0.lastPathComponent.hasPrefix("rollout-") }
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
            return ParsedState(sessions: try discoverSessions(), checkpoint: nil)
        }

        var checkpoint: CodexCheckpoint
        if reset {
            checkpoint = CodexCheckpoint()
        } else if let previous, let carried = previous.checkpoint as? CodexCheckpoint {
            checkpoint = carried
        } else {
            checkpoint = CodexCheckpoint()
        }

        for line in lines {
            checkpoint.fold(line)
        }

        let session = checkpoint.buildSession(
            agent: kind,
            fallbackDate: source.modified
        )
        return ParsedState(sessions: session.map { [$0] } ?? [], checkpoint: checkpoint)
    }

    // MARK: - Full parse

    public func discoverSessions() throws -> [Session] {
        let files: [URL]
        if let file {
            files = [file]
        } else if let sessionsRoot {
            files = try jsonlFiles(under: sessionsRoot)
                .filter { $0.lastPathComponent.hasPrefix("rollout-") }
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
        var checkpoint = CodexCheckpoint()
        for line in lines {
            checkpoint.fold(line)
        }
        return checkpoint.buildSession(
            agent: kind,
            fallbackDate: fileModificationDate(file) ?? Date()
        )
    }
}

// MARK: - Codex checkpoint

/// Per-file running summary for a Codex rollout. `thread_token_usage` is
/// cumulative, so folding REPLACES the stored usage rather than adding to it.
struct CodexCheckpoint: AdapterCheckpoint {
    var sessionID: String?
    var cwd: String?
    var model: String?
    var usage = TokenUsage.zero
    var earliest: Date?
    var latest: Date?
    var lastRecordType: String?
    var lastEventKind: String?

    mutating func fold(_ line: String) {
        guard let record = jsonObject(line) else { return }

        let type = record["type"] as? String
        if let type { lastRecordType = type }

        // The end-of-turn signal lives in payload.type, not the outer type:
        // every lifecycle event arrives as an "event_msg" whose payload carries
        // task_started / item_completed / task_complete.
        if type == "event_msg",
           let payload = record["payload"] as? [String: Any],
           let eventType = payload["type"] as? String {
            lastEventKind = eventType
        }

        if let raw = record["timestamp"] as? String, let ts = parseISODate(raw) {
            if earliest == nil || ts < earliest! { earliest = ts }
            if latest == nil || ts > latest! { latest = ts }
        }

        guard let payload = record["payload"] as? [String: Any] else { return }

        switch type {
        case "session_meta":
            if sessionID == nil { sessionID = payload["session_id"] as? String }
            if cwd == nil { cwd = payload["cwd"] as? String }
            if model == nil { model = Self.findModel(in: payload) }
        case "turn_context":
            if cwd == nil {
                cwd = (payload["cwd"] as? String) ?? (payload["workspace_roots"] as? [String])?.first
            }
        case "token_usage_record":
            if let cumulative = payload["thread_token_usage"] as? [String: Any] {
                // Cumulative: the latest value IS the total. Replace, never add.
                usage = TokenUsage(
                    input: jsonInt(cumulative["input_tokens"]),
                    output: jsonInt(cumulative["output_tokens"]),
                    cacheCreation: jsonInt(cumulative["cache_write_input_tokens"]),
                    cacheRead: jsonInt(cumulative["cached_input_tokens"])
                )
            }
        default:
            break
        }
    }

    func buildSession(agent: AgentKind, fallbackDate: Date) -> Session? {
        guard let id = sessionID else { return nil }

        let started = earliest ?? fallbackDate
        let last = latest ?? started

        // Codex marks end of turn in payload.type, not the outer record type.
        // Reading only the outer type makes every finished session look like it
        // is still producing, so it ages into `stalled` and never reports "your
        // turn".
        let lastEvent: LastEventKind
        switch lastEventKind {
        case "task_complete":
            lastEvent = .turnComplete
        case "task_started", "item_completed", "token_count":
            lastEvent = .producing
        default:
            switch lastRecordType {
            case "event_msg", "response_item": lastEvent = .producing
            default: lastEvent = .unknown
            }
        }

        return Session(
            id: id,
            agent: agent,
            cwd: cwd ?? "",
            gitBranch: nil,
            model: model,
            state: .idle,
            startedAt: started,
            lastActivity: last,
            usage: usage,
            lastEvent: lastEvent
        )
    }

    /// Prefers a specific model name when present (e.g.
    /// `base_instructions.provenance.model`); otherwise falls back to
    /// `model_provider` (e.g. `"openai"`), which is the only model identifier
    /// Codex's `session_meta` always exposes.
    static func findModel(in payload: [String: Any]) -> String? {
        if let found = recursivelyFindModel(in: payload) { return found }
        return payload["model_provider"] as? String
    }

    static func recursivelyFindModel(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let model = dict["model"] as? String { return model }
            for (_, child) in dict {
                if let found = recursivelyFindModel(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = recursivelyFindModel(in: child) { return found }
            }
        }
        return nil
    }
}
