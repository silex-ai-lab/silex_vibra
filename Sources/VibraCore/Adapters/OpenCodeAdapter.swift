import Foundation
import SQLite3

/// Reads sessions from the OpenCode SQLite database.
///
/// Security contract (all mandatory):
/// - The file is opened read-only (`SQLITE_OPEN_READONLY` plus a `mode=ro`
///   file URI), so Vibra is structurally incapable of corrupting the live DB.
/// - Only a hardcoded allowlist of columns on the `session` table is read.
///   `SELECT *` is never used.
/// - The `account`, `credential`, `account_state`, and `control_account`
///   tables (which hold tokens) are never referenced.
/// - Raw rows are never logged, printed, or surfaced; errors are generic.
public struct OpenCodeAdapter: AgentAdapter {
    public let kind: AgentKind = .openCode

    private let dbURL: URL

    public init(dbURL: URL = VibraPaths.openCodeDB) {
        self.dbURL = dbURL
    }

    public var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dbURL.path, isDirectory: &isDir) && !isDir.boolValue
    }

    // MARK: - Incremental ingest

    /// SQLite is not JSONL, so this returns a single descriptor and the ingest
    /// layer re-runs the query on every change. The descriptor folds the WAL
    /// sidecar files into size/mtime — see `describeDatabase`.
    public func sources() throws -> [SourceDescriptor] {
        guard isAvailable else { return [] }
        guard let descriptor = Self.describeDatabase(dbURL) else { return [] }
        return [descriptor]
    }

    /// Change-detection descriptor for a SQLite database. In WAL mode the main
    /// `.db` file's size and mtime can stay FIXED while data flows through
    /// `opencode.db-wal`; fingerprinting only the `.db` would make Vibra go
    /// permanently stale. Fold `-wal` (and `-shm`) in when they exist.
    static func describeDatabase(_ url: URL) -> SourceDescriptor? {
        guard let main = SourceDescriptor.describing(url) else { return nil }

        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let shmURL = URL(fileURLWithPath: url.path + "-shm")

        var size = main.size
        var modified = main.modified
        if let wal = SourceDescriptor.describing(walURL) {
            size += wal.size
            if wal.modified > modified { modified = wal.modified }
        }
        if let shm = SourceDescriptor.describing(shmURL) {
            size += shm.size
            if shm.modified > modified { modified = shm.modified }
        }

        return SourceDescriptor(
            url: main.url,
            deviceID: main.deviceID,
            fileID: main.fileID,
            size: size,
            modified: modified
        )
    }

    // MARK: - Reporting

    /// OpenCode stores per-session totals with no per-record timestamps, so its
    /// usage is real but undatable. A fabricated day would be worse than an
    /// honest "day unknown", so this returns no samples and `ReportBuilder`
    /// reports the totals on its undated line.
    public func usageSamples(from records: [String]) -> [UsageSample] {
        []
    }

    // MARK: - Allowlist

    /// The single table this adapter may read.
    static let allowedTables = ["session"]

    /// The exact columns read from `session`.
    static let sessionColumns = [
        "id", "directory", "title", "model",
        "tokens_input", "tokens_output",
        "tokens_cache_read", "tokens_cache_write",
        "time_created", "time_updated", "permission",
    ]

    /// The only SELECT this adapter emits.
    static let sessionSelectSQL =
        "SELECT id, directory, title, model, tokens_input, tokens_output, " +
        "tokens_cache_read, tokens_cache_write, " +
        "time_created, time_updated, permission FROM session ORDER BY time_updated DESC"

    /// Every SQL string this adapter can emit, surfaced for the security test.
    static var allSQL: [String] {
        [sessionSelectSQL, "PRAGMA table_info(session)"]
    }

    // MARK: - Discovery

    public func discoverSessions() throws -> [Session] {
        guard isAvailable else { return [] }

        let uri = "file:\(dbURL.path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw OpenCodeError.unavailable
        }
        defer { sqlite3_close(db) }

        guard verifySchema(db) else { return [] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.sessionSelectSQL, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw OpenCodeError.unavailable
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnText(statement, 0) ?? ""
            let directory = columnText(statement, 1) ?? ""
            let title = columnText(statement, 2)
            let model = Self.parseModel(columnText(statement, 3))

            let input = columnInt(statement, 4)
            let output = columnInt(statement, 5)
            let cacheRead = columnInt(statement, 6)
            let cacheWrite = columnInt(statement, 7)
            let createdMS = columnInt(statement, 8)
            let updatedMS = columnInt(statement, 9)
            let permission = columnText(statement, 10)

            let usage = TokenUsage(
                input: input,
                output: output,
                cacheCreation: cacheWrite,
                cacheRead: cacheRead
            )

            // OpenCode's only sitting-on-approval signal is a non-empty
            // `permission` column. There is no reliable "producing" vs
            // "turn complete" marker in the session table, so anything else
            // is `.unknown`.
            let lastEvent: LastEventKind =
                (permission?.isEmpty == false) ? .permissionPrompt : .unknown

            sessions.append(Session(
                id: id,
                agent: kind,
                cwd: directory,
                model: model,
                state: .idle,
                startedAt: Date(timeIntervalSince1970: Double(createdMS) / 1000.0),
                lastActivity: Date(timeIntervalSince1970: Double(updatedMS) / 1000.0),
                usage: usage,
                title: title,
                lastEvent: lastEvent
            ))
        }
        return sessions
    }

    // MARK: - Schema verification

    /// Confirms every allowlisted column exists before querying. A mismatch
    /// (e.g. a newer OpenCode schema) yields `false` and the caller returns `[]`
    /// rather than falling back to a broader query.
    private func verifySchema(_ db: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(session)", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        var present = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = columnText(statement, 1) { present.insert(name) }
        }
        return Self.sessionColumns.allSatisfy { present.contains($0) }
    }

    // MARK: - Column accessors

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: c)
    }

    private func columnInt(_ statement: OpaquePointer?, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    /// The `model` column is JSON such as `{"id":"deepseek-chat",...}`. Return
    /// the `id`, or the raw string when it is not JSON.
    private static func parseModel(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else {
            return value
        }
        return id
    }
}

public enum OpenCodeError: Error, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "OpenCode database is unavailable."
    }
}
