import Foundation
import Testing
@testable import VibraCore

struct OpenCodeAdapterTests {
    private let sessionSchema = """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, title TEXT, model TEXT, \
        tokens_input INTEGER, tokens_output INTEGER, \
        tokens_cache_read INTEGER, tokens_cache_write INTEGER, \
        time_created INTEGER, time_updated INTEGER, permission TEXT);
        """

    @Test func sqlNeverReferencesAccountOrCredential() {
        for sql in OpenCodeAdapter.allSQL {
            let lower = sql.lowercased()
            #expect(!lower.contains("account"))
            #expect(!lower.contains("credential"))
        }
    }

    @Test func canaryTokenNeverLeaks() throws {
        let canary = "VIBRA_CANARY_MUST_NOT_LEAK"
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("opencode.db")

        let sql = [
            sessionSchema,
            """
            INSERT INTO session VALUES ('ses_test_1','/Users/demo/workplace/sample','benign title',\
            '{"id":"deepseek-chat","providerID":"deepseek"}',1000,200,400,500,1789877120102,1789877509576,NULL);
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
        #expect(rawBytes.range(of: Data(canary.utf8)) != nil)

        let adapter = OpenCodeAdapter(dbURL: dbURL)
        var sessions: [Session] = []
        var thrown: (any Error)?
        do {
            sessions = try adapter.discoverSessions()
        } catch {
            thrown = error
        }

        if let error = thrown {
            #expect(!error.localizedDescription.contains(canary))
        }
        #expect(thrown == nil)

        #expect(sessions.count == 1)

        for session in sessions {
            #expect(!session.id.contains(canary))
            #expect(!session.cwd.contains(canary))
            #expect(!(session.title ?? "").contains(canary))
            #expect(!(session.model ?? "").contains(canary))
        }
        let encoded = try JSONEncoder().encode(sessions)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(canary))
    }

    @Test func readOnlyDoesNotMutateFixtureDB() throws {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("ro.db")

        let sql = [
            sessionSchema,
            """
            INSERT INTO session VALUES ('ses_test_1','/Users/demo/workplace/sample','title',\
            '{"id":"deepseek-chat","providerID":"deepseek"}',1000,200,400,500,1789877120102,1789877509576,NULL);
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

        #expect(sessions.count == 1)
        #expect(before == after)
    }

    @Test func permissionColumnMapsToLastEvent() throws {
        let dir = testScratchDirectory().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("perm.db")

        let sql = [
            sessionSchema,
            """
            INSERT INTO session VALUES ('ses_pending','/Users/demo/workplace/sample','t',\
            '{"id":"deepseek-chat"}',0,0,0,0,1789877120102,1789877509576,'ask');
            """,
            """
            INSERT INTO session VALUES ('ses_quiet','/Users/demo/workplace/sample','t',\
            '{"id":"deepseek-chat"}',0,0,0,0,1789877120102,1789877509576,NULL);
            """,
        ]
        try makeDB(at: dbURL, statements: sql)

        let sessions = try OpenCodeAdapter(dbURL: dbURL).discoverSessions()
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        #expect(byID["ses_pending"]?.lastEvent == .permissionPrompt)
        #expect(byID["ses_quiet"]?.lastEvent == .unknown)
    }
}
