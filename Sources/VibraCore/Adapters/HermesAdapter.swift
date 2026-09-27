import Foundation
import SQLite3

/// Reads sessions from Hermes Agent's SQLite store, `~/.hermes/state.db`.
///
/// Security contract (all mandatory), the same as `OpenCodeAdapter`'s:
/// - Opened read-only (`SQLITE_OPEN_READONLY` plus a `mode=ro` file URI).
/// - Only the `sessions` and `messages` tables, only allowlisted columns,
///   never `SELECT *`. A schema that lacks an allowlisted column yields no
///   sessions rather than a broader query.
/// - The status path (`statusSQL`) never selects `messages.content`. The one
///   statement that does (`historySQL`) runs only when the user opens the
///   History window.
/// - `~/.hermes` also holds `.env` and `auth.json`, which contain secrets.
///   Nothing here ever opens them: this adapter knows one path, `state.db`.
/// - Raw rows are never logged or printed; errors are generic.
///
/// Schema observed 2026-09-26, `schema_version` 17; see
/// docs/PLAN-2026-09-26-history-query-settings-hermes.md, T1 "Provenance".
public struct HermesAdapter: AgentAdapter {
    public let kind: AgentKind = .hermes

    private let dbURL: URL
    /// Called with every SQL string this adapter prepares. Test-only: it is
    /// how the suite proves the status path never prepares `historySQL`.
    private let onPrepare: (@Sendable (String) -> Void)?

    public init(dbURL: URL = VibraPaths.hermesStateDB, onPrepare: (@Sendable (String) -> Void)? = nil) {
        self.dbURL = dbURL
        self.onPrepare = onPrepare
    }

    public var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dbURL.path, isDirectory: &isDir) && !isDir.boolValue
    }

    /// One descriptor for the database, with its WAL sidecars folded in.
    public func sources() throws -> [SourceDescriptor] {
        guard isAvailable, let descriptor = OpenCodeAdapter.describeDatabase(dbURL) else { return [] }
        return [descriptor]
    }

    /// Hermes keeps per-session token totals only.
    public var reportsUndatedTotals: Bool { true }

    // MARK: - Allowlist

    static let allowedTables = ["sessions", "messages"]

    static let sessionColumns = [
        "id", "source", "model", "started_at", "ended_at", "cwd", "git_branch", "title",
        "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens",
        "archived", "parent_session_id",
    ]

    /// `messages` columns the status path reads. `content` is not one of them.
    static let messageStatusColumns = ["id", "session_id", "role", "finish_reason", "timestamp", "active"]

    static let sessionsSQL =
        "SELECT id, source, model, started_at, ended_at, cwd, git_branch, title, " +
        "input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, " +
        "parent_session_id FROM sessions WHERE archived = 0"

    /// The latest active conversational message of one open session. Served
    /// by `idx_messages_session (session_id, timestamp)`: one indexed
    /// single-row lookup per open session, whatever the message volume.
    static let lastMessageSQL =
        "SELECT role, finish_reason, timestamp FROM messages WHERE session_id = ? " +
        "AND active = 1 AND role IN ('user','assistant','tool') " +
        "ORDER BY timestamp DESC, id DESC LIMIT 1"

    /// The only statement that selects message text. History window only.
    static let historySQL =
        "SELECT m.session_id, m.timestamp, m.content, s.cwd FROM messages m " +
        "JOIN sessions s ON s.id = m.session_id WHERE m.role = 'user' AND m.active = 1 " +
        "AND m.timestamp >= ? AND s.archived = 0 AND s.source <> 'subagent' " +
        "ORDER BY m.timestamp"

    static let schemaSQL = ["PRAGMA table_info(sessions)", "PRAGMA table_info(messages)"]

    /// Everything the status path may prepare.
    static var statusSQL: [String] { schemaSQL + [sessionsSQL, lastMessageSQL] }
    /// Everything the history path may prepare.
    static var historyOnlySQL: [String] { schemaSQL + [historySQL] }

    // MARK: - Discovery

    public func discoverSessions() throws -> [Session] {
        guard isAvailable else { return [] }
        let db = try open()
        defer { sqlite3_close(db) }
        guard columns(db, "sessions").isSuperset(of: Self.sessionColumns),
              columns(db, "messages").isSuperset(of: Self.messageStatusColumns)
        else { return [] }

        var sessions: [Session] = []
        try query(db, Self.sessionsSQL) { row in
            let id = text(row, 0) ?? ""
            let source = text(row, 1)
            let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(row, 3))
            let ended = sqlite3_column_type(row, 4) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: sqlite3_column_double(row, 4))
            // `reasoning_tokens` is deliberately not added: it may already be
            // inside `output_tokens`, and double counting is worse than omission.
            let usage = TokenUsage(
                input: int(row, 8),
                output: int(row, 9),
                cacheCreation: int(row, 11),
                cacheRead: int(row, 10)
            )
            sessions.append(Session(
                id: id,
                agent: kind,
                cwd: text(row, 5) ?? "",
                gitBranch: text(row, 6),
                model: text(row, 2),
                state: .idle,
                startedAt: startedAt,
                lastActivity: ended ?? startedAt,
                usage: usage,
                title: text(row, 7),
                lastEvent: ended == nil ? .unknown : .settled,
                entrypoint: source
            ))
        }

        // An ended session is settled and needs no message read. Each open
        // one gets its latest active message.
        for index in sessions.indices where sessions[index].lastEvent != .settled {
            try query(db, Self.lastMessageSQL, bind: sessions[index].id) { row in
                let role = text(row, 0)
                let finish = text(row, 1)
                sessions[index].lastActivity = Date(timeIntervalSince1970: sqlite3_column_double(row, 2))
                sessions[index].lastEvent = Self.lastEvent(role: role, finishReason: finish)
            }
        }
        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// What the latest message says about the turn. Hermes records no
    /// approval state we can see, so this never yields `.permissionPrompt`.
    static func lastEvent(role: String?, finishReason: String?) -> LastEventKind {
        switch (role, finishReason) {
        case ("assistant", "stop"), ("assistant", "length"): .turnComplete
        case ("assistant", "tool_calls"), ("tool", _), ("user", _): .producing
        default: .unknown
        }
    }

    // MARK: - History

    public func storedQuestions(since cutoff: Date) -> [QuestionRecord] {
        guard isAvailable, let db = try? open() else { return [] }
        defer { sqlite3_close(db) }
        guard columns(db, "sessions").isSuperset(of: ["id", "cwd", "archived", "source"]),
              columns(db, "messages").isSuperset(of: ["session_id", "timestamp", "content", "role", "active"])
        else { return [] }

        var records: [QuestionRecord] = []
        try? query(db, Self.historySQL, bind: cutoff.timeIntervalSince1970) { row in
            guard let text = QuestionRecord.normalized(text(row, 2)) else { return }
            records.append(QuestionRecord(
                agent: kind,
                sessionID: self.text(row, 0) ?? "",
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(row, 1)),
                cwd: self.text(row, 3) ?? "",
                text: text
            ))
        }
        return records
    }

    // MARK: - SQLite

    private func open() throws -> OpaquePointer? {
        let uri = "file:\(dbURL.path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw HermesError.unavailable
        }
        return db
    }

    private func columns(_ db: OpaquePointer?, _ table: String) -> Set<String> {
        let sql = table == "sessions" ? Self.schemaSQL[0] : Self.schemaSQL[1]
        var present = Set<String>()
        try? query(db, sql) { row in
            if let name = text(row, 1) { present.insert(name) }
        }
        return present
    }

    private func query(
        _ db: OpaquePointer?,
        _ sql: String,
        bind value: Any? = nil,
        row: (OpaquePointer) throws -> Void
    ) throws {
        onPrepare?(sql)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw HermesError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        switch value {
        case let text as String:
            sqlite3_bind_text(statement, 1, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case let number as Double:
            sqlite3_bind_double(statement, 1, number)
        default:
            break
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            try row(statement)
        }
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: c)
    }

    private func int(_ statement: OpaquePointer?, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }
}

public enum HermesError: Error, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Hermes database is unavailable."
    }
}
