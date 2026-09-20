import Foundation

/// Reads Codex sessions from `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// The `session_meta` record identifies the session (id, cwd, model) and the
/// `token_usage_record` records carry `thread_token_usage`, which is cumulative
/// across the thread. The last `thread_token_usage` seen therefore holds the
/// session total.
public struct CodexAdapter: AgentAdapter {
    public let kind: AgentKind = .codex

    private let sessionsRoot: URL

    public init(sessionsRoot: URL = VibraPaths.codexSessions) {
        self.sessionsRoot = sessionsRoot
    }

    public var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: sessionsRoot.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func discoverSessions() throws -> [Session] {
        let files = try jsonlFiles(under: sessionsRoot)
        var sessions: [Session] = []
        for file in files where file.lastPathComponent.hasPrefix("rollout-") {
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

        for line in lines {
            guard let record = jsonObject(line) else { continue }

            if let raw = record["timestamp"] as? String, let ts = parseISODate(raw) {
                if startedAt == nil || ts < startedAt! { startedAt = ts }
                if lastActivity == nil || ts > lastActivity! { lastActivity = ts }
            }

            guard let payload = record["payload"] as? [String: Any] else { continue }

            switch record["type"] as? String {
            case "session_meta":
                if sessionID == nil { sessionID = payload["session_id"] as? String }
                if cwd == nil { cwd = payload["cwd"] as? String }
                if model == nil { model = findModel(in: payload) }
                if startedAt == nil, let raw = payload["timestamp"] as? String {
                    startedAt = parseISODate(raw)
                }
            case "token_usage_record":
                if let cumulative = payload["thread_token_usage"] as? [String: Any] {
                    threadUsage = cumulative
                }
            default:
                break
            }
        }

        guard let id = sessionID else { return nil }

        let usage = TokenUsage(
            input: jsonInt(threadUsage?["input_tokens"]),
            output: jsonInt(threadUsage?["output_tokens"]) + jsonInt(threadUsage?["reasoning_output_tokens"]),
            cacheCreation: jsonInt(threadUsage?["cache_write_input_tokens"]),
            cacheRead: jsonInt(threadUsage?["cached_input_tokens"])
        )

        let started = startedAt ?? fileModificationDate(file) ?? Date()
        let last = lastActivity ?? started

        return Session(
            id: id,
            agent: kind,
            cwd: cwd ?? "",
            gitBranch: nil,
            model: model,
            state: .idle,
            startedAt: started,
            lastActivity: last,
            usage: usage
        )
    }

    /// The model string lives at `base_instructions.provenance.model`. Fall back
    /// to a recursive search for the first `model` string key in the payload.
    private func findModel(in payload: [String: Any]) -> String? {
        if let base = payload["base_instructions"] as? [String: Any],
           let provenance = base["provenance"] as? [String: Any],
           let model = provenance["model"] as? String {
            return model
        }
        return recursivelyFindModel(in: payload)
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
