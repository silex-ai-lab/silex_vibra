import Foundation
import Testing
@testable import VibraCore

struct CodexAdapterTests {
    @Test func discoversSessionWithModelAndCwd() throws {
        let adapter = CodexAdapter(file: fixtureURL("Fixtures/codex_rollout.jsonl"))
        #expect(adapter.isAvailable)

        let sessions = try adapter.discoverSessions()
        #expect(sessions.count == 1)

        let session = try #require(sessions.first)
        #expect(session.agent == .codex)
        #expect(session.id == "01a07f27-1111-2222-3333-000000000002")
        #expect(session.cwd == "/Users/demo/workplace/sample")
        #expect(session.model == "openai")
    }

    @Test func threadUsageIsCumulativeNotSummed() throws {
        let adapter = CodexAdapter(file: fixtureURL("Fixtures/codex_rollout.jsonl"))
        let session = try #require(adapter.discoverSessions().first)

        // The fixture's two token_usage_records have thread_token_usage of
        // input 1000 then 2500; summing them would wrongly give 3500. The
        // adapter must report the LAST cumulative value, not the sum.
        #expect(session.usage.input == 2500)
        #expect(session.usage.output == 350)
        #expect(session.usage.cacheRead == 1300)
        #expect(session.usage.cacheCreation == 0)
    }

    @Test func lastEventIsProducing() throws {
        // The fixture ends with an `event_msg`, which means Codex is still
        // emitting output.
        let adapter = CodexAdapter(file: fixtureURL("Fixtures/codex_rollout.jsonl"))
        let session = try #require(adapter.discoverSessions().first)
        #expect(session.lastEvent == .producing)
    }
}
