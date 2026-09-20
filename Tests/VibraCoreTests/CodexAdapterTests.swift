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

    @Test func trailingTaskCompleteMeansTurnIsOver() throws {
        // The end-of-turn signal is payload.type == "task_complete", NOT the
        // outer record type. Reading only the outer type makes every finished
        // Codex session look like it is still producing, so it ages into
        // `stalled` and never reports "your turn" - which is the whole point
        // of the app.
        let adapter = CodexAdapter(file: fixtureURL("Fixtures/codex_rollout.jsonl"))
        let session = try #require(adapter.discoverSessions().first)
        #expect(session.lastEvent == .turnComplete)
    }

    @Test func trailingItemCompletedMeansStillProducing() throws {
        let body = """
        {"timestamp":"2026-09-18T11:00:00.000Z","ordinal":0,"type":"session_meta","payload":{"session_id":"mid-turn-1","cwd":"/fake/proj","cli_version":"0.153.4","model_provider":"openai"}}
        {"timestamp":"2026-09-18T11:00:10.000Z","ordinal":5,"type":"event_msg","payload":{"type":"item_completed"}}
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-midturn-\(UUID().uuidString).jsonl")
        try body.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = try #require(CodexAdapter(file: url).discoverSessions().first)
        #expect(session.lastEvent == .producing)
    }
}
