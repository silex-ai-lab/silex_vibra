import Foundation
import Testing
@testable import VibraCore

struct ClaudeCodeAdapterTests {
    @Test func discoversSessionWithUsageAndCwd() throws {
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/claude_session.jsonl"))
        #expect(adapter.isAvailable)

        let sessions = try adapter.discoverSessions()
        #expect(sessions.count == 1)

        let session = try #require(sessions.first)
        #expect(session.agent == .claudeCode)
        #expect(session.id == "cef2869f-aaaa-bbbb-cccc-000000000001")
        #expect(session.cwd == "/Users/demo/workplace/sample")
        #expect(session.model == "claude-opus-5")
        #expect(session.gitBranch == "main")

        // usage summed across both assistant records
        #expect(session.usage.input == 15)
        #expect(session.usage.output == 500)
        #expect(session.usage.cacheCreation == 1000)
        #expect(session.usage.cacheRead == 11000)
        #expect(session.usage.total > 0)

        // oldest timestamp -> startedAt, newest -> lastActivity
        #expect(session.startedAt < session.lastActivity)
    }

    @Test func missingFileIsUnavailable() {
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/does-not-exist.jsonl"))
        #expect(!adapter.isAvailable)
        #expect(adapter.discoverSessionsSafely().isEmpty)
    }

    @Test func lastEventIsPermissionPrompt() throws {
        // The fixture ends with a `permission-mode` record, which means the
        // agent is parked on an approval prompt regardless of the earlier
        // assistant `end_turn`.
        let adapter = ClaudeCodeAdapter(file: fixtureURL("Fixtures/claude_session.jsonl"))
        let session = try #require(adapter.discoverSessions().first)
        #expect(session.lastEvent == .permissionPrompt)
    }
}
