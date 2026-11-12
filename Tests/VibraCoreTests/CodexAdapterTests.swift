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
        try (body + "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let session = try #require(CodexAdapter(file: url).discoverSessions().first)
        #expect(session.lastEvent == .producing)
    }

    private func lastEvent(ofRollout records: [String]) throws -> LastEventKind? {
        let meta = #"{"timestamp":"2026-11-12T17:00:00.000Z","type":"session_meta","payload":{"session_id":"turn-owner-1","cwd":"/fake/proj","originator":"codex-tui","model_provider":"openai"}}"#
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-owner-\(UUID().uuidString).jsonl")
        try (([meta] + records).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try CodexAdapter(file: url).discoverSessions().first?.lastEvent
    }

    private func turn(trigger: String, prompt: String) -> [String] {
        [
            #"{"timestamp":"2026-11-12T17:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_attribution":{"turn_trigger":"\#(trigger)"}}}"#,
            #"{"timestamp":"2026-11-12T17:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"\#(prompt)"}]}}"#,
            #"{"timestamp":"2026-11-12T17:00:09.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#,
        ]
    }

    @Test func turnTheHumanStartedEndsAsTheirTurn() throws {
        #expect(try lastEvent(ofRollout: turn(trigger: "user", prompt: "fix the build")) == .turnComplete)
        #expect(try lastEvent(ofRollout: turn(trigger: "realtime", prompt: "fix the build")) == .turnComplete)
    }

    @Test func scheduledAutomationRunEndsSettled() throws {
        // A Codex app automation's run is a report nobody is expected to answer.
        let run = turn(trigger: "automation_heartbeat_scheduled", prompt: "# AGENTS.md instructions")
        #expect(try lastEvent(ofRollout: run) == .settled)
    }

    @Test func fleetDispatchEndsSettled() throws {
        // A fleet planner typed this into the seat's terminal and reads the
        // reply file itself; the rollout still records the trigger as "user".
        let dispatch = turn(trigger: "user", prompt: "Dispatch codex-impl-r4: read /tmp/fleet/prompt.txt and follow it exactly.")
        #expect(try lastEvent(ofRollout: dispatch) == .settled)
    }

    @Test func humanTurnAfterADispatchIsTheirTurnAgain() throws {
        let records = turn(trigger: "user", prompt: "Dispatch codex-impl-r4: read /tmp/p.txt")
            + turn(trigger: "user", prompt: "what did you change?")
        #expect(try lastEvent(ofRollout: records) == .turnComplete)
    }
}
