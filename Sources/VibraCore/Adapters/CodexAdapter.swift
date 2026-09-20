import Foundation

/// Reads Codex sessions from `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// The `session_meta` record identifies the session (id, cwd, model) and the
/// `token_usage_record` records carry `thread_token_usage`, which is cumulative
/// across the thread. The last `thread_token_usage` seen therefore holds the
/// session total; summing `thread_token_usage` across records would multi-count.
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

    // MARK: - Parsing

    private func parseSession(at file: URL) -> Session? {
        guard let lines = readLines(file) else { return nil }

        var sessionID: String?
        var cwd: String?
        var model: String?
        var startedAt: Date?
        var lastActivity: Date?
        var threadUsage: [String: Any]?
        var lastRecordType: String?
        var lastEventKind: String?

        for line in lines {
            guard let record = jsonObject(line) else { continue }

            let type = record["type"] as? String
            if let type { lastRecordType = type }

            // The end-of-turn signal lives in payload.type, not the outer
            // type: every lifecycle event arrives as an "event_msg" whose
            // payload carries task_started / item_completed / task_complete.
            if type == "event_msg",
               let payload = record["payload"] as? [String: Any],
               let eventType = payload["type"] as? String {
                lastEventKind = eventType
            }

            if let raw = record["timestamp"] as? String, let ts = parseISODate(raw) {
                if startedAt == nil || ts < startedAt! { startedAt = ts }
                if lastActivity == nil || ts > lastActivity! { lastActivity = ts }
            }

            guard let payload = record["payload"] as? [String: Any] else { continue }

            switch type {
            case "session_meta":
                if sessionID == nil { sessionID = payload["session_id"] as? String }
                if cwd == nil { cwd = payload["cwd"] as? String }
                if model == nil { model = findModel(in: payload) }
                if startedAt == nil, let raw = payload["timestamp"] as? String {
                    startedAt = parseISODate(raw)
                }
            case "turn_context":
                if cwd == nil {
                    cwd = (payload["cwd"] as? String) ?? (payload["workspace_roots"] as? [String])?.first
                }
            case "token_usage_record":
                // thread_token_usage is cumulative; the last one wins.
                if let cumulative = payload["thread_token_usage"] as? [String: Any] {
                    threadUsage = cumulative
                }
            default:
                break
            }
        }

        guard let id = sessionID else { return nil }

        // Codex field names differ from Claude's:
        //   cached_input_tokens      -> cacheRead
        //   cache_write_input_tokens -> cacheCreation
        let usage = TokenUsage(
            input: jsonInt(threadUsage?["input_tokens"]),
            output: jsonInt(threadUsage?["output_tokens"]),
            cacheCreation: jsonInt(threadUsage?["cache_write_input_tokens"]),
            cacheRead: jsonInt(threadUsage?["cached_input_tokens"])
        )

        let started = startedAt ?? fileModificationDate(file) ?? Date()
        let last = lastActivity ?? started

        // Codex does mark end of turn, but in payload.type rather than the
        // outer record type: a trailing `task_complete` means the turn is
        // finished and the human has the ball. Reading only the outer type
        // makes every finished Codex session look like it is still producing,
        // so it ages into `stalled` and never reports "your turn".
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
            agent: kind,
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
    private func findModel(in payload: [String: Any]) -> String? {
        if let found = recursivelyFindModel(in: payload) { return found }
        return payload["model_provider"] as? String
    }

    private func recursivelyFindModel(in value: Any) -> String? {
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
