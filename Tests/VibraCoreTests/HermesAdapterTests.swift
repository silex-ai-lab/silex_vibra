import Foundation
import SQLite3
import Testing
@testable import VibraCore

/// Records every SQL string an adapter prepares.
final class PreparedSQL: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    func record(_ sql: String) { lock.lock(); seen.append(sql); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return seen }
}

struct HermesAdapterTests {
    /// A temp `.hermes` directory holding the fixture db, plus the secret
    /// files a real one has next to it.
    private func makeHermesHome(extraSQL: [String] = []) throws -> (dir: URL, db: URL) {
        let dir = testScratchDirectory().appendingPathComponent("hermes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("state.db")
        let sql = try String(contentsOf: fixtureURL("Fixtures/hermes_state.sql"), encoding: .utf8)
        try makeDB(at: db, statements: [sql] + extraSQL)
        return (dir, db)
    }

    private func sessions(_ db: URL) throws -> [String: Session] {
        let list = try HermesAdapter(dbURL: db).discoverSessions()
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    @Test func stateRulesFollowTheLatestActiveMessage() throws {
        let (dir, db) = try makeHermesHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try sessions(db)

        #expect(s["h_turn"]?.lastEvent == .turnComplete)
        #expect(s["h_tool"]?.lastEvent == .producing)
        #expect(s["h_toolres"]?.lastEvent == .producing)
        #expect(s["h_user"]?.lastEvent == .producing)
        #expect(s["h_length"]?.lastEvent == .turnComplete)
        // The rewound (inactive) user message is ignored.
        #expect(s["h_rewound"]?.lastEvent == .turnComplete)
        #expect(s["h_rewound"]?.lastActivity == Date(timeIntervalSince1970: 1790000070))
        // A trailing session_meta row is not conversation.
        #expect(s["h_meta"]?.lastEvent == .turnComplete)
        #expect(s["h_meta"]?.lastActivity == Date(timeIntervalSince1970: 1790000090))
        // No messages: unknown, active since it started.
        #expect(s["h_nomsg"]?.lastEvent == .unknown)
        #expect(s["h_nomsg"]?.lastActivity == Date(timeIntervalSince1970: 1790000050))
        // Ended: settled at its end time, however recent.
        #expect(s["h_ended"]?.lastEvent == .settled)
        #expect(s["h_ended"]?.lastActivity == Date(timeIntervalSince1970: 1790000900))
        #expect(s["h_gateway"]?.lastEvent == .turnComplete)
        // Never a permission prompt: Hermes records none we can see.
        #expect(!s.values.contains { $0.lastEvent == .permissionPrompt })
    }

    @Test func archivedDroppedAndSubagentUnattended() throws {
        let (dir, db) = try makeHermesHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try sessions(db)

        #expect(s["h_archived"] == nil)
        #expect(s.count == 11)
        #expect(s["h_sub"]?.entrypoint == "subagent")
        #expect(s["h_sub"]?.isUnattended == true)
        #expect(s["h_gateway"]?.entrypoint == "feishu")
        #expect(s["h_gateway"]?.isUnattended == false)
        #expect(s["h_turn"]?.isUnattended == false)
    }

    @Test func fieldsAndUsageMapWithoutReasoningTokens() throws {
        let (dir, db) = try makeHermesHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let turn = try #require(try sessions(db)["h_turn"])

        #expect(turn.agent == .hermes)
        #expect(turn.cwd == "/Users/demo/proj-a")
        #expect(turn.gitBranch == "main")
        #expect(turn.model == "demo-model")
        #expect(turn.usage == TokenUsage(input: 100, output: 20, cacheCreation: 1, cacheRead: 5))
    }

    @Test func schemaMismatchYieldsNothing() throws {
        let dir = testScratchDirectory().appendingPathComponent("hermes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("state.db")
        // A future schema that renamed `active`.
        try makeDB(at: db, statements: [
            "CREATE TABLE sessions (id TEXT, source TEXT, model TEXT, started_at REAL, ended_at REAL, cwd TEXT, git_branch TEXT, title TEXT, input_tokens INT, output_tokens INT, cache_read_tokens INT, cache_write_tokens INT, archived INT, parent_session_id TEXT);",
            "CREATE TABLE messages (id INTEGER PRIMARY KEY, session_id TEXT, role TEXT, content TEXT, finish_reason TEXT, timestamp REAL, is_live INT);",
            "INSERT INTO sessions VALUES ('x','cli','m',1,NULL,'/tmp','main',NULL,0,0,0,0,0,NULL);",
        ])
        #expect(try HermesAdapter(dbURL: db).discoverSessions().isEmpty)
        #expect(HermesAdapter(dbURL: db).storedQuestions(since: .distantPast).isEmpty)
    }

    // MARK: - SQL discipline

    @Test func statusSQLNeverSelectsContent() {
        for sql in HermesAdapter.statusSQL {
            #expect(!sql.lowercased().contains("content"), "status SQL selects content: \(sql)")
        }
        #expect(HermesAdapter.historySQL.lowercased().contains("content"))
    }

    @Test func everyStatementStaysOnAllowedTables() {
        let known = ["sessions", "messages"]
        for sql in HermesAdapter.statusSQL + HermesAdapter.historyOnlySQL {
            let lower = sql.lowercased()
            #expect(!lower.contains("select *"))
            #expect(!lower.contains(".env") && !lower.contains("auth"))
            // Every FROM / JOIN names an allowed table.
            let pattern = try! NSRegularExpression(pattern: #"(?:from|join)\s+([a-z_]+)"#)
            for match in pattern.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
                let table = String(lower[Range(match.range(at: 1), in: lower)!])
                #expect(known.contains(table), "unexpected table \(table)")
            }
        }
    }

    @Test func statusPathPreparesOnlyStatusSQL() throws {
        let (dir, db) = try makeHermesHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let seen = PreparedSQL()
        _ = try HermesAdapter(dbURL: db, onPrepare: { seen.record($0) }).discoverSessions()

        #expect(!seen.all.isEmpty)
        for sql in seen.all {
            #expect(HermesAdapter.statusSQL.contains(sql), "status path prepared \(sql)")
        }
        #expect(!seen.all.contains(HermesAdapter.historySQL))
        // Ended sessions need no message read: one lookup per open session.
        let open = try sessions(db).values.filter { $0.lastEvent != .settled }.count
        #expect(seen.all.filter { $0 == HermesAdapter.lastMessageSQL }.count == open)
    }

    @Test func lastMessageLookupUsesTheSessionIndex() throws {
        let (dir, db) = try makeHermesHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        var handle: OpaquePointer?
        #expect(sqlite3_open(db.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(handle, "EXPLAIN QUERY PLAN " + HermesAdapter.lastMessageSQL, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var plan: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let c = sqlite3_column_text(statement, 3) { plan.append(String(cString: c)) }
        }
        let text = plan.joined(separator: "\n")
        #expect(text.contains("SEARCH messages USING INDEX"), "\(text)")
        #expect(!text.contains("SCAN messages"), "\(text)")
        #expect(!text.contains("TEMP B-TREE"), "\(text)")
    }

    // MARK: - Canary

    @Test func hermesCanaryNeverLeaks() throws {
        let canary = "VIBRA_HERMES_CANARY_MUST_NOT_LEAK"
        let (dir, db) = try makeHermesHome(extraSQL: [
            "INSERT INTO messages (session_id, role, content, timestamp, active) VALUES ('h_turn','user','\(canary)',1790000015,1);",
            "UPDATE sessions SET system_prompt = '\(canary)' WHERE id = 'h_tool';",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        try "API_KEY=\(canary)\n".write(to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "{\"token\":\"\(canary)\"}".write(to: dir.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let rawBytes = try Data(contentsOf: db)
        #expect(rawBytes.range(of: Data(canary.utf8)) != nil)

        let list = try HermesAdapter(dbURL: db).discoverSessions()
        #expect(!list.isEmpty)
        let encoded = try JSONEncoder().encode(list)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(canary))

        let query = try QueryOutput(sessions: list, settings: .defaults, now: Date()).json()
        #expect(!String(decoding: query, as: UTF8.self).contains(canary))

        #expect(!(HermesError.unavailable.errorDescription ?? "").contains(canary))
    }

    @Test func descriptorChangesWhenOnlyTheWALChanges() throws {
        let (dir, db) = try makeHermesHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = HermesAdapter(dbURL: db)
        let before = try #require(try adapter.sources().first)
        try Data(repeating: 1, count: 64).write(to: URL(fileURLWithPath: db.path + "-wal"))
        let after = try #require(try adapter.sources().first)
        #expect(before.size != after.size)
    }

    // MARK: - History

    @Test func storedQuestionsAreUserMessagesSinceCutoff() throws {
        let (dir, db) = try makeHermesHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = HermesAdapter(dbURL: db)

        let all = adapter.storedQuestions(since: Date(timeIntervalSince1970: 0))
        let texts = Set(all.map(\.text))
        #expect(texts.contains("first question in proj-a"))
        #expect(texts.contains("chat from the gateway"))
        #expect(texts.contains("question in ended session"))
        #expect(!texts.contains("rewound away"))         // inactive
        #expect(!texts.contains("archived question"))    // archived
        #expect(!texts.contains("subagent instruction")) // unattended
        #expect(!texts.contains("an answer"))            // not a user message
        #expect(all.allSatisfy { $0.agent == .hermes })
        #expect(all.first { $0.text == "first question in proj-a" }?.project == "proj-a")

        let late = adapter.storedQuestions(since: Date(timeIntervalSince1970: 1790000060))
        #expect(Set(late.map(\.text)) == ["question in ended session", "chat from the gateway"])
    }
}
