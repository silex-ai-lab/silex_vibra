import Foundation
import Testing
@testable import VibraCore

/// Cursor's state database holds its auth tokens next to the agent sessions,
/// so the adapter is held to OpenCode's contract: read-only, one allowlisted
/// query, and nothing from the token table can come out.
struct CursorAdapterTests {

    private func header(_ fields: String) -> String {
        #"{"type":"head",\#(fields),"workspaceIdentifier":{"id":"1"}}"#
    }

    private func makeCursorDB(canary: String) throws -> (URL, URL) {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("state.vscdb")
        let now = 1_790_000_000_000
        try makeDB(at: db, statements: [
            "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);",
            "INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', '\(canary)');",
            "CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);",
            """
            CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, \
            createdAt INTEGER, lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, \
            recency INTEGER, checkpointAt INTEGER, value TEXT, subagentTypeName TEXT);
            """,
            "INSERT INTO composerHeaders VALUES ('gen','1',\(now),\(now),0,0,0,NULL,'\(header(#""name":"Refactor auth","hasUnreadMessages":false"#))',NULL);",
            "INSERT INTO cursorDiskKV VALUES ('composerData:gen', '{\"status\":\"generating\",\"generatingBubbleIds\":[\"b1\"],\"blobEncryptionKey\":\"\(canary)\"}');",
            "INSERT INTO composerHeaders VALUES ('approve','1',\(now),\(now),0,0,0,NULL,'\(header(#""name":"Run migrations","hasBlockingPendingActions":true"#))',NULL);",
            "INSERT INTO composerHeaders VALUES ('done','1',\(now),\(now),0,0,0,NULL,'\(header(#""name":"Write tests","hasUnreadMessages":true"#))',NULL);",
            "INSERT INTO composerHeaders VALUES ('draft','1',\(now),\(now),0,0,0,NULL,'\(header(#""isDraft":true"#))',NULL);",
            "INSERT INTO composerHeaders VALUES ('old','1',\(now),\(now),1,0,0,NULL,'\(header(#""name":"Archived","isArchived":true"#))',NULL);",
            "INSERT INTO composerHeaders VALUES ('sub','1',\(now),\(now),0,1,0,NULL,'\(header(#""name":"subagent""#))',NULL);",
        ])
        return (dir, db)
    }

    @Test func readsSessionsWithCursorsOwnStateSignals() throws {
        let (dir, db) = try makeCursorDB(canary: "VIBRA_CURSOR_CANARY")
        defer { try? FileManager.default.removeItem(at: dir) }

        let sessions = try CursorAdapter(dbURL: db).discoverSessions()
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        // Drafts, archived chats and subagents are not sessions to show.
        #expect(Set(byID.keys) == ["gen", "approve", "done"])
        #expect(byID["gen"]?.lastEvent == .producing)
        #expect(byID["approve"]?.lastEvent == .permissionPrompt)
        #expect(byID["done"]?.lastEvent == .turnComplete)
        #expect(byID["gen"]?.displayName == "Refactor auth")
        #expect(byID["gen"]?.agent == .cursor)
    }

    @Test func tokenTableAndRecordBodiesNeverSurface() throws {
        let canary = "VIBRA_CURSOR_CANARY_MUST_NOT_LEAK"
        let (dir, db) = try makeCursorDB(canary: canary)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rendered = String(describing: try CursorAdapter(dbURL: db).discoverSessions())
        #expect(!rendered.contains(canary))
        for sql in CursorAdapter.allSQL {
            #expect(!sql.contains("ItemTable"), "the token table must never be queried")
            #expect(!sql.uppercased().contains("SELECT *"))
        }
    }

    @Test func aSeenReplyIsIdleNotYourTurn() {
        let row = CursorAdapter.Row(
            id: "x", createdMS: 1, updatedMS: 2, name: " ", hasUnread: false,
            hasBlockingActions: false, isArchived: false, isDraft: false,
            workspacePath: "/w/app", status: "completed", generatingCount: 0
        )
        let session = CursorAdapter.session(from: row)
        #expect(session?.lastEvent == .settled)
        #expect(session?.displayName == "Cursor chat")
        #expect(session?.projectName == "app")
    }

    /// Measured on Cursor 3.18: at send the record is rewritten with status
    /// "aborted" and the header is left alone until the reply is done.
    @Test func aRecordNewerThanItsHeaderIsATurnInFlight() {
        var row = CursorAdapter.Row(
            id: "x", createdMS: 1_000, updatedMS: 14_930_000, name: "Kernel", hasUnread: false,
            hasBlockingActions: false, isArchived: false, isDraft: false,
            workspacePath: nil, status: "aborted", generatingCount: 0,
            recordUpdatedMS: 15_003_000, checkpointMS: 15_005_000
        )
        let running = CursorAdapter.session(from: row)
        #expect(running?.lastEvent == .producing)
        #expect(running?.lastActivity == Date(timeIntervalSince1970: 15_005))

        // Partway through, the header catches up; "aborted" still says running.
        row.updatedMS = 15_003_000
        #expect(CursorAdapter.session(from: row)?.lastEvent == .producing)

        // Finished: header caught up, status completed.
        row.updatedMS = 15_003_000
        row.status = "completed"
        #expect(CursorAdapter.session(from: row)?.lastEvent == .settled)

        // A completed record touched later (renamed, reopened) is not a turn.
        row.recordUpdatedMS = 16_000_000
        #expect(CursorAdapter.session(from: row)?.lastEvent == .settled)
    }

    @Test func codexExecRunsAreUnattended() {
        let at = Date(timeIntervalSince1970: 1)
        func codex(_ originator: String) -> Session {
            Session(id: originator, agent: .codex, cwd: "/p", state: .awaitingInput,
                    startedAt: at, lastActivity: at, entrypoint: originator)
        }
        #expect(codex("codex_exec").isUnattended)
        #expect(!codex("codex-tui").isUnattended)
        #expect(!codex("codex_exec").wantsNotification)
    }
}
