import Foundation
import Testing
@testable import VibraCore

/// The detail window's first screen: what is true now, how Vibra knows, and
/// whether the return button can honestly promise anything.
struct SessionDetailModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(
        _ id: String = "a",
        agent: AgentKind = .claudeCode,
        state: SessionState = .awaitingInput,
        cwd: String = "/fake/payments",
        title: String? = nil,
        branch: String? = "main",
        lastActivity: Date? = nil,
        usage: TokenUsage = .zero,
        lastEvent: LastEventKind = .turnComplete
    ) -> Session {
        Session(
            id: id, agent: agent, cwd: cwd, gitBranch: branch,
            state: state, startedAt: now.addingTimeInterval(-3600),
            lastActivity: lastActivity ?? now.addingTimeInterval(-300),
            usage: usage, title: title, lastEvent: lastEvent)
    }

    private func build(
        _ session: Session,
        live: Bool = true,
        health: [AgentKind: SourceHealth] = [:],
        attention: [SessionKey: AttentionStart] = [:]
    ) -> SessionDetailModel {
        SessionDetailModel.build(
            session: session,
            snapshot: StatusSnapshot(
                sessions: live ? [session] : [], health: health, attention: attention),
            now: now)
    }

    @Test func aLiveSessionShowsMetadataEvidenceAndTokens() {
        let s = session(usage: TokenUsage(input: 100, output: 23))
        let detail = build(
            s,
            health: [.claudeCode: .ready(lastSuccess: now)],
            attention: [s.key: .observed(now.addingTimeInterval(-240))])

        #expect(detail.heading == "payments")
        #expect(detail.agentName == "Claude Code")
        #expect(detail.branch == "main")
        #expect(detail.stateLine == "your turn · 4m")
        #expect(detail.evidenceLine
            == "The agent's last turn ended; waiting for you to reply is inferred from that.")
        #expect(detail.lastObservedLine == "Last activity 5m ago")
        #expect(detail.healthLine == "Reading normally")
        #expect(detail.tokensLine == "123 tokens")
        #expect(detail.cwd == "/fake/payments")
        #expect(detail.returnRoute == .attempt)
        #expect(detail.isLive)
        #expect(detail.historyAvailable)
    }

    @Test func aMissingBranchIsReportedRatherThanGuessed() {
        #expect(build(session(branch: nil)).branch == "Not reported")
    }

    @Test func aVanishedSessionKeepsItsMetadataButSaysItIsGone() {
        let s = session()
        let detail = build(s, live: false, health: [.claudeCode: .failing(.readFailed, lastSuccess: now)])
        #expect(detail.isLive == false)
        #expect(detail.stateLine == "No longer active")
        #expect(detail.heading == "payments")
        #expect(detail.healthLine
            == "Couldn't read this agent's data (last read <1m ago). This session may be out of date.")
    }

    @Test func healthLinesCoverReadyFailingAndAbsent() {
        #expect(build(session(), health: [.claudeCode: .ready(lastSuccess: now)]).healthLine
            == "Reading normally")
        #expect(build(session(), health: [
            .claudeCode: .failing(.readFailed, lastSuccess: now.addingTimeInterval(-180)),
        ]).healthLine
            == "Couldn't read this agent's data (last read 3m ago). This session may be out of date.")
        #expect(build(session(), health: [
            .claudeCode: .failing(.parseFailed, lastSuccess: nil),
        ]).healthLine
            == "Couldn't read this agent's data (never read). This session may be out of date.")
        #expect(build(session(), health: [.claudeCode: .absent]).healthLine == "No data source on disk")
        #expect(build(session(), health: [:]).healthLine == "No data source on disk")
    }

    @Test func anEmptyUsageTotalReadsAsNoneReported() {
        #expect(build(session(usage: .zero)).tokensLine == "None reported")
    }

    @Test func evidenceMatchesTheLastRecordAndTheState() {
        #expect(build(session(state: .blocked, lastEvent: .permissionPrompt)).evidenceLine
            == "Observed a permission prompt in the session.")
        #expect(build(session(state: .working, lastEvent: .producing)).evidenceLine
            == "The agent wrote output recently.")
        #expect(build(session(state: .stalled, lastEvent: .producing)).evidenceLine
            == "The agent was mid-turn and has written nothing since.")
        #expect(build(session(state: .idle, lastEvent: .settled)).evidenceLine
            == "The session reported it had finished.")
        #expect(build(session(state: .idle, lastEvent: .unknown)).evidenceLine
            == "Vibra can't tell from this agent's data; inferred from last activity.")
    }

    @Test func returnRouteAndHistoryFollowTheAgent() {
        let openCode = build(session(agent: .openCode, cwd: "/fake/oc"))
        #expect(openCode.returnRoute == .none)
        #expect(openCode.historyAvailable == false)

        let cursor = build(session(agent: .cursor, cwd: "/fake/cur"))
        #expect(cursor.returnRoute == .focusApp)

        let hermes = build(session(agent: .hermes, cwd: "/fake/hermes"))
        #expect(hermes.returnRoute == .none)
        #expect(hermes.historyAvailable)
    }
}
