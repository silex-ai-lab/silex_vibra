import XCTest
@testable import VibraCore

final class OpenCodeAdapterTests: XCTestCase {
    private let sessionSchema = """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, model TEXT, \
        tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER, \
        tokens_cache_read INTEGER, tokens_cache_write INTEGER, \
        time_created INTEGER, time_updated INTEGER);
        """

    func testSQLNeverReferencesAccountOrCredential() {
        for sql in OpenCodeAdapter.allSQL {
            let lower = sql.lowercased()
            XCTAssertFalse(lower.contains("account"), "SQL references an account table: \(sql)")
            XCTAssertFalse(lower.contains("credential"), "SQL references a credential table: \(sql)")
        }
    }

    func testCanaryTokenNeverLeaks() throws {
        let canary = "VIBRA_CANARY_MUST_NOT_LEAK"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibra-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("opencode.db")

        let sql = [
            sessionSchema,
            """
            INSERT INTO session VALUES ('ses_test_1','/tmp/vibra-test','benign title',\
            '{"id":"deepseek-chat","providerID":"deepseek"}',1000,200,300,400,500,1789877120102,1789877509576);
            """,
            "CREATE TABLE account (id TEXT PRIMARY KEY, access_token TEXT, refresh_token TEXT);",
            "INSERT INTO account VALUES ('acct_1','\(canary)','refresh_123');",
            "CREATE TABLE credential (id TEXT PRIMARY KEY, token TEXT);",
            "INSERT INTO credential VALUES ('cred_1','another_secret');",
        ]
        try makeDB(at: dbURL, statements: sql)

        // Prove the canary is genuinely present in the raw file, so the check
        // that it does NOT surface in our output is meaningful.
        let rawBytes = try Data(contentsOf: dbURL)
        XCTAssertNotNil(rawBytes.range(of: Data(canary.utf8)), "fixture DB should contain the canary")

        let adapter = OpenCodeAdapter(dbURL: dbURL)
        var sessions: [Session] = []
        do {
            sessions = try adapter.discoverSessions()
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(canary))
            return XCTFail("adapter threw: \(error)")
        }

        XCTAssertEqual(sessions.count, 1)

        // Not in the returned sessions, nor in their Codable encoding.
        for session in sessions {
            XCTAssertFalse(session.id.contains(canary))
            XCTAssertFalse(session.cwd.contains(canary))
            XCTAssertFalse((session.title ?? "").contains(canary))
            XCTAssertFalse((session.model ?? "").contains(canary))
        }
        let encoded = try JSONEncoder().encode(sessions)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(canary))
    }

    func testReadOnlyDoesNotMutateFixtureDB() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibra-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("ro.db")

        let sql = [
            sessionSchema,
            """
            INSERT INTO session VALUES ('ses_test_1','/tmp/vibra-test','title',\
            '{"id":"deepseek-chat","providerID":"deepseek"}',1000,200,300,400,500,1789877120102,1789877509576);
            """,
        ]
        try makeDB(at: dbURL, statements: sql)

        // Strip write permission: opening read-only must still succeed.
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dbURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dbURL.path)
        }

        let before = try fileSignature(dbURL)
        let sessions = try OpenCodeAdapter(dbURL: dbURL).discoverSessions()
        let after = try fileSignature(dbURL)

        XCTAssertEqual(sessions.count, 1, "read-only open should still return the row")
        XCTAssertEqual(before, after, "the database file must be byte-identical after a read")
    }

    func testRealDBReadOnlyNoMutation() throws {
        let dbURL = VibraPaths.openCodeDB
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw XCTSkip("no opencode.db on this machine")
        }

        let before = try fileSignature(dbURL)
        _ = OpenCodeAdapter(dbURL: dbURL).discoverSessions()
        let after = try fileSignature(dbURL)

        XCTAssertEqual(before, after, "opening the live DB read-only must not mutate it")
    }
}
