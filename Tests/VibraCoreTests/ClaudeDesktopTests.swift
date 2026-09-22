import Foundation
import Testing
@testable import VibraCore

/// Claude UI sessions: the desktop app parks a quiet session's process but
/// keeps the session open, so "no process" must not mean "gone" for them -
/// while archived ones and finished scheduled runs still go.
struct ClaudeDesktopTests {

    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func s(
        _ id: String,
        _ state: SessionState,
        task: String? = nil
    ) -> Session {
        Session(id: id, agent: .claudeCode, cwd: "/w/proj", state: state,
                startedAt: at, lastActivity: at, scheduledTask: task)
    }

    @Test func parsesOnlyTheFieldsItNeeds() {
        let data = Data(#"""
        {"sessionId":"local_c269fcbb-f6b2-451a-bcdc-ab91f2298dda",
         "cliSessionId":"f0f118d6-3161-47d4-a12d-648064c4161b",
         "title":"  Splunk agentic SOC 关系分析 ","isArchived":false,
         "remoteMcpServersConfig":[{"url":"https://example.invalid/mcp"}],
         "promptAppendSnapshot":{"append":"long system text"}}
        """#.utf8)
        let parsed = ClaudeDesktopIndex.parse(data)
        #expect(parsed?.0 == "f0f118d6-3161-47d4-a12d-648064c4161b")
        #expect(parsed?.1 == DesktopSessionInfo(
            localID: "local_c269fcbb-f6b2-451a-bcdc-ab91f2298dda",
            title: "Splunk agentic SOC 关系分析",
            isArchived: false
        ))
    }

    @Test func refusesALocalIDTheDeepLinkWouldNotAccept() {
        let data = Data(#"{"sessionId":"local_x&q=1","cliSessionId":"a"}"#.utf8)
        #expect(ClaudeDesktopIndex.parse(data) == nil)
    }

    @Test func enrichmentAppliesTitleDesktopIDAndDropsArchived() {
        let out = Session.enriched(
            [s("open", .awaitingInput), s("archived", .awaitingInput), s("cli", .awaitingInput)],
            desktop: [
                "open": DesktopSessionInfo(localID: "local_1", title: "My chat", isArchived: false),
                "archived": DesktopSessionInfo(localID: "local_2", title: nil, isArchived: true),
            ],
            live: [:]
        )
        #expect(out.map(\.id) == ["open", "cli"])
        #expect(out[0].displayName == "My chat")
        #expect(out[0].desktopSessionID == "local_1")
        #expect(out[1].displayName == "proj")
    }

    @Test func liveStatusOverridesTheTranscriptGuess() {
        let out = Session.enriched(
            [s("perm", .awaitingInput), s("busy", .idle), s("idle", .awaitingInput)],
            desktop: [:],
            live: [
                "perm": ClaudeLiveStatus(status: "waiting", waitingFor: "permission prompt"),
                "busy": ClaudeLiveStatus(status: "busy", waitingFor: nil),
                "idle": ClaudeLiveStatus(status: "idle", waitingFor: nil),
            ]
        )
        #expect(out.map(\.state) == [.blocked, .working, .awaitingInput])
    }

    @Test func parkedClaudeUISessionStaysButFinishedScheduledRunGoes() {
        var parked = s("parked", .awaitingInput)
        parked.desktopSessionID = "local_1"
        var run = s("run", .awaitingInput, task: "hourly-sync")
        run.desktopSessionID = "local_2"
        let kept = Session.withoutExited(
            [parked, run, s("exited-cli", .awaitingInput)],
            live: [.claudeCode: []]
        )
        #expect(kept.map(\.id) == ["parked"])
    }
}
