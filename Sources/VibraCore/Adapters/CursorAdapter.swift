import Foundation
import SQLite3

/// Reads Cursor agent and chat sessions ("composers") from Cursor's global
/// state database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
///
/// Security contract, the same as `OpenCodeAdapter`'s and for the same reason
/// - this database also holds Cursor's auth tokens:
/// - Opened read-only (`SQLITE_OPEN_READONLY` plus a `mode=ro` file URI).
/// - One hardcoded SELECT. It reads the `composerHeaders` table (Cursor's own
///   per-session summary) and, from each session's `composerData` record, only
///   `status`, the length of `generatingBubbleIds` and two timestamps,
///   extracted inside SQLite
///   with `json_extract` - the rest of that record (conversation text,
///   encryption keys) never leaves the database.
/// - `ItemTable`, which holds the auth tokens, is never referenced.
/// - Raw rows are never logged, printed, or surfaced.
public struct CursorAdapter: AgentAdapter {
    public let kind: AgentKind = .cursor

    private let dbURL: URL

    public init(dbURL: URL = VibraPaths.cursorStateDB) {
        self.dbURL = dbURL
    }

    public var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dbURL.path, isDirectory: &isDir) && !isDir.boolValue
    }

    public func sources() throws -> [SourceDescriptor] {
        guard isAvailable, let descriptor = OpenCodeAdapter.describeDatabase(dbURL) else { return [] }
        return [descriptor]
    }

    // MARK: - Allowlist

    /// The exact columns `composerHeaders` must have before it is queried.
    static let headerColumns = ["composerId", "createdAt", "lastUpdatedAt", "isSubagent", "value"]

    /// The only SELECT this adapter emits.
    static let sessionSelectSQL = """
        SELECT h.composerId, h.createdAt, h.lastUpdatedAt, \
        json_extract(h.value, '$.name'), \
        json_extract(h.value, '$.hasUnreadMessages'), \
        json_extract(h.value, '$.hasBlockingPendingActions'), \
        json_extract(h.value, '$.isArchived'), \
        json_extract(h.value, '$.isDraft'), \
        json_extract(h.value, '$.workspaceIdentifier.uri.fsPath'), \
        json_extract(CAST(d.value AS TEXT), '$.status'), \
        json_array_length(json_extract(CAST(d.value AS TEXT), '$.generatingBubbleIds')), \
        json_extract(CAST(d.value AS TEXT), '$.lastUpdatedAt'), \
        json_extract(h.value, '$.conversationCheckpointLastUpdatedAt'), \
        json_extract(CAST(d.value AS TEXT), '$.conversationCheckpointLastUpdatedAt') \
        FROM composerHeaders h \
        LEFT JOIN cursorDiskKV d ON d.key = 'composerData:' || h.composerId \
        WHERE h.isSubagent = 0 \
        ORDER BY h.lastUpdatedAt DESC
        """

    /// Every SQL string this adapter can emit, surfaced for the security test.
    static var allSQL: [String] {
        [sessionSelectSQL, "PRAGMA table_info(composerHeaders)"]
    }

    // MARK: - Discovery

    public func discoverSessions() throws -> [Session] {
        guard isAvailable else { return [] }

        let uri = "file:\(dbURL.path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw CursorError.unavailable
        }
        defer { sqlite3_close(db) }
        // Cursor writes this database constantly; wait briefly on its lock
        // rather than failing the refresh.
        sqlite3_busy_timeout(db, 200)

        guard verifySchema(db) else { return [] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.sessionSelectSQL, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw CursorError.unavailable
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let row = Self.row(from: statement) else { continue }
            if let session = Self.session(from: row) { sessions.append(session) }
        }
        return sessions
    }

    /// One `composerHeaders` row, already reduced to the allowlisted fields.
    struct Row: Equatable {
        var id: String
        var createdMS: Int
        var updatedMS: Int?
        var name: String?
        var hasUnread: Bool
        var hasBlockingActions: Bool
        var isArchived: Bool
        var isDraft: Bool
        var workspacePath: String?
        var status: String?
        var generatingCount: Int
        /// When the session's full record was last written. Cursor writes it
        /// the moment a message is sent; the header only catches up when the
        /// turn ends.
        var recordUpdatedMS: Int? = nil
        /// Latest conversation checkpoint, which Cursor also writes mid-turn.
        var checkpointMS: Int? = nil

        /// A turn is running. Cursor 3.18 never writes "generating": at send
        /// it rewrites the record with status "aborted" and keeps that until
        /// the reply is done, when it becomes "completed". The header catches
        /// up partway through the turn, so a record newer than its header only
        /// covers the first seconds of a turn (measured 2026-09-22).
        ///
        /// A turn you stopped is left "aborted" too. The two are told apart by
        /// silence: see `Session.settlingOrphaned`.
        var isMidTurn: Bool {
            if status == "aborted" { return true }
            guard let record = recordUpdatedMS, let header = updatedMS else { return false }
            return record > header && status != "completed"
        }
    }

    /// Maps a row to a session, or nil for a draft or archived one.
    ///
    /// Cursor says outright what the other agents make Vibra infer: an action
    /// awaiting approval (`hasBlockingPendingActions`), a reply in progress
    /// (`status` "generating", bubbles still generating, or - in Cursor 3.18,
    /// which writes neither - `Row.isMidTurn`), and a finished
    /// reply nobody has looked at yet (`hasUnreadMessages`). Once read, a
    /// finished session is idle rather than "your turn" - you have seen it.
    static func session(from row: Row) -> Session? {
        guard !row.isDraft, !row.isArchived, row.id != "empty-state-draft" else { return nil }

        let lastEvent: LastEventKind
        if row.hasBlockingActions {
            lastEvent = .permissionPrompt
        } else if row.status == "generating" || row.generatingCount > 0 || row.isMidTurn {
            lastEvent = .producing
        } else if row.hasUnread {
            lastEvent = .turnComplete
        } else if row.status == "completed" {
            lastEvent = .settled
        } else {
            lastEvent = .unknown
        }

        let created = Date(timeIntervalSince1970: Double(row.createdMS) / 1000)
        let updated = [row.updatedMS, row.recordUpdatedMS, row.checkpointMS]
            .compactMap { $0.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
            .max() ?? created
        let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Session(
            id: row.id,
            agent: .cursor,
            cwd: row.workspacePath ?? "",
            state: .idle,
            startedAt: created,
            lastActivity: max(created, updated),
            title: (name?.isEmpty ?? true) ? "Cursor chat" : name,
            lastEvent: lastEvent
        )
    }

    private static func row(from statement: OpaquePointer) -> Row? {
        guard let id = text(statement, 0) else { return nil }
        return Row(
            id: id,
            createdMS: Int(sqlite3_column_int64(statement, 1)),
            updatedMS: sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, 2)),
            name: text(statement, 3),
            hasUnread: sqlite3_column_int(statement, 4) != 0,
            hasBlockingActions: sqlite3_column_int(statement, 5) != 0,
            isArchived: sqlite3_column_int(statement, 6) != 0,
            isDraft: sqlite3_column_int(statement, 7) != 0,
            workspacePath: text(statement, 8),
            status: text(statement, 9),
            generatingCount: Int(sqlite3_column_int(statement, 10)),
            recordUpdatedMS: int64(statement, 11),
            checkpointMS: [int64(statement, 12), int64(statement, 13)].compactMap { $0 }.max()
        )
    }

    /// A newer Cursor with a different schema yields no sessions rather than a
    /// broader query.
    private func verifySchema(_ db: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(composerHeaders)", -1, &statement, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(statement) }
        var present = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = Self.text(statement, 1) { present.insert(name) }
        }
        return Self.headerColumns.allSatisfy { present.contains($0) }
    }

    private static func int64(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, index))
    }

    private static func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: c)
    }
}

public enum CursorError: Error, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Cursor state database is unavailable."
    }
}
