import Foundation
import Testing
@testable import VibraCore

/// The menu's whole job is to put the session that needs you on top and say
/// something true about every other row, so these pin the ordering, the wait
/// text and the disambiguation rules rather than the exact pixel layout.
struct SessionMenuModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(
        _ id: String,
        agent: AgentKind = .claudeCode,
        state: SessionState = .working,
        cwd: String = "/fake/proj",
        title: String? = nil,
        branch: String? = nil,
        model: String? = nil,
        lastActivity: Date? = nil,
        usage: TokenUsage = .zero,
        lastEvent: LastEventKind = .unknown,
        desktopSessionID: String? = nil
    ) -> Session {
        Session(
            id: id, agent: agent, cwd: cwd, gitBranch: branch, model: model,
            state: state, startedAt: now.addingTimeInterval(-3600),
            lastActivity: lastActivity ?? now, usage: usage, title: title,
            lastEvent: lastEvent, desktopSessionID: desktopSessionID)
    }

    private func model(_ sessions: [Session],
                       health: [AgentKind: SourceHealth] = [:],
                       attention: [SessionKey: AttentionStart] = [:]) -> SessionMenuModel {
        SessionMenuModel.build(
            StatusSnapshot(sessions: sessions, health: health, attention: attention), now: now)
    }

    // MARK: - Ordering

    @Test func attentionRowsPrecedeRunningRowsAcrossSixAgents() {
        let states: [SessionState] = [.blocked, .awaitingInput, .working, .stalled, .idle]
        var sessions: [Session] = []
        var attention: [SessionKey: AttentionStart] = [:]
        for agent in AgentKind.allCases {
            for (index, state) in states.enumerated() {
                let s = session("\(agent.rawValue)-\(index)", agent: agent, state: state,
                                cwd: "/fake/\(agent.rawValue)-\(index)")
                sessions.append(s)
                if state.needsAttention {
                    attention[s.key] = .observed(now.addingTimeInterval(-300))
                }
            }
        }

        let built = model(sessions, attention: attention)
        #expect(built.sections.map(\.kind) == [.needsYou, .running, .recent])
        #expect(built.sections.map { $0.rows.count } == [12, 12, 6])
        #expect(built.detailRows.count == 30)

        // Approvals outrank finished turns, across every agent.
        let byKey = Dictionary(uniqueKeysWithValues: sessions.map { ($0.key, $0) })
        let needsYouStates = built.sections[0].rows.compactMap { byKey[$0.key]?.state }
        #expect(needsYouStates.prefix(6).allSatisfy { $0 == .blocked })
        #expect(needsYouStates.suffix(6).allSatisfy { $0 == .awaitingInput })
    }

    @Test func tiesBreakDeterministicallyByActivityThenKey() {
        let older = now.addingTimeInterval(-60)
        let sameMoment = [
            session("b", agent: .codex, state: .working, cwd: "/fake/one", lastActivity: older),
            session("a", agent: .claudeCode, state: .working, cwd: "/fake/two", lastActivity: older),
            session("a", agent: .claudeCode, state: .working, cwd: "/fake/three", lastActivity: now),
        ]
        let built = model(sameMoment)
        // Newest first, then agent rawValue, then id.
        #expect(built.detailRows.map(\.key.id) == ["a", "a", "b"])
        #expect(built.detailRows.map(\.key.agent) == [.claudeCode, .claudeCode, .codex])
    }

    // MARK: - Labels

    @Test func sameLabelBranchAndPathFallThroughToASharedIdPrefix() {
        let a = session("abcd1111-aaaa", state: .working, cwd: "/fake/payments", branch: "main")
        let b = session("abcd2222-bbbb", state: .idle, cwd: "/fake/payments", branch: "main")
        let built = model([a, b])
        let titles = built.detailRows.map(\.title)

        #expect(titles.count == 2)
        #expect(titles[0] != titles[1])
        #expect(titles.contains { $0.hasPrefix("payments / main / fake/payments #abcd1 ") })
        #expect(titles.contains { $0.hasPrefix("payments / main / fake/payments #abcd2 ") })
    }

    @Test func aBranchAloneSeparatesTwoRows() {
        let a = session("a", cwd: "/fake/payments", branch: "main")
        let b = session("b", cwd: "/fake/payments", branch: "feature")
        let titles = model([a, b]).detailRows.map(\.title)
        #expect(titles.contains { $0.hasPrefix("payments / main ") })
        #expect(titles.contains { $0.hasPrefix("payments / feature ") })
        #expect(!titles.contains { $0.contains("#") })
    }

    @Test func aPathSeparatesRowsWhenNeitherHasABranch() {
        let a = session("a", cwd: "/work/payments")
        let b = session("b", cwd: "/archive/payments")
        let titles = model([a, b]).detailRows.map(\.title)
        #expect(titles.contains { $0.hasPrefix("payments / work/payments ") })
        #expect(titles.contains { $0.hasPrefix("payments / archive/payments ") })
        #expect(!titles.contains { $0.contains("#") })
    }

    @Test func uniqueLabelsAreLeftAlone() {
        let built = model([session("a", cwd: "/fake/payments")])
        #expect(built.detailRows.first?.title == "payments · Claude Code · working")
    }

    // MARK: - Wait and state text

    @Test func waitTextDistinguishesObservedFromFirstSeen() {
        let observed = session("observed", state: .awaitingInput, cwd: "/fake/observed")
        let firstSeen = session("first-seen", state: .awaitingInput, cwd: "/fake/first-seen")
        let unknown = session("unknown", state: .awaitingInput, cwd: "/fake/unknown")
        let built = model(
            [observed, firstSeen, unknown],
            attention: [
                observed.key: .observed(now.addingTimeInterval(-240)),
                firstSeen.key: .firstSeen(now.addingTimeInterval(-240)),
            ])
        let titles = built.detailRows.map(\.title)
        #expect(titles.contains { $0.hasSuffix("· your turn · 4m") })
        #expect(titles.contains { $0.hasSuffix("· your turn · first seen 4m ago") })
        #expect(titles.contains { $0.hasSuffix("· your turn") })
    }

    @Test func stalledRowsSayHowLongTheyHaveBeenQuiet() {
        let stalled = session("s", state: .stalled, lastActivity: now.addingTimeInterval(-8 * 60))
        #expect(model([stalled]).detailRows.first?.title.hasSuffix("· no activity for 8m") == true)
    }

    @Test func durationBandsAreFloored() {
        #expect(formatDuration(0) == "<1m")
        #expect(formatDuration(59) == "<1m")
        #expect(formatDuration(60) == "1m")
        #expect(formatDuration(3_599) == "59m")
        #expect(formatDuration(3_600) == "1h")
        #expect(formatDuration(86_399) == "23h")
        #expect(formatDuration(86_400) == "1d")
        #expect(formatDuration(3 * 86_400 + 5) == "3d")
    }

    // MARK: - Empty state and notices

    @Test func noSessionsWithAReadableAgentSaysNoActiveSessions() {
        let built = model([], health: [.claudeCode: .ready(lastSuccess: now)])
        #expect(built.emptyMessage == "No active sessions")
        #expect(built.notices.isEmpty)
    }

    @Test func noSessionsAndNoSourceNamesWhatToStart() {
        let built = model([], health: [.claudeCode: .absent, .codex: .absent])
        #expect(built.emptyMessage == "No sessions yet. Start Claude Code, Codex, Cursor, VS Code, "
            + "OpenCode or Hermes and it appears here.")
        #expect(built.emptyMessage?.contains("not installed") == false)
        #expect(built.emptyMessage?.contains("not found") == false)
    }

    @Test func aFailingSourceReplacesTheEmptyMessageWithANotice() {
        let built = model([], health: [.claudeCode: .failing(.readFailed, lastSuccess: now.addingTimeInterval(-180))])
        #expect(built.emptyMessage == nil)
        #expect(built.notices == ["Couldn't read Claude Code data (last read 3m ago)"])
    }

    @Test func aNeverReadSourceSaysSo() {
        let built = model([], health: [.claudeCode: .failing(.listFailed, lastSuccess: nil)])
        #expect(built.notices == ["Couldn't read Claude Code data (never read)"])
    }

    @Test func noticesAppearAlongsideSessionsAndInAgentOrder() {
        let built = model(
            [session("a")],
            health: [
                .hermes: .failing(.parseFailed, lastSuccess: now),
                .claudeCode: .failing(.readFailed, lastSuccess: now),
            ])
        #expect(built.emptyMessage == nil)
        #expect(built.detailRows.count == 1)
        #expect(built.notices == [
            "Couldn't read Claude Code data (last read <1m ago)",
            "Couldn't read Hermes data (last read <1m ago)",
        ])
    }

    // MARK: - Click and tooltip

    @Test func rowsReturnWhenTheyCanAndOpenDetailsOtherwise() {
        let claude = session("c", agent: .claudeCode)
        let openCode = session("o", agent: .openCode, cwd: "/fake/oc")
        let titles = model([claude, openCode]).detailRows
        #expect(titles.first { $0.key.agent == .claudeCode }?.click == .returnToSession)
        #expect(titles.first { $0.key.agent == .openCode }?.click == .openDetails)
    }

    @Test func tooltipsCarryTokensAndAnHonestAction() throws {
        let withTokens = session("a", model: "m", usage: TokenUsage(input: 100, output: 20))
        let without = session("b", agent: .openCode, cwd: "/fake/oc")
        let rows = model([withTokens, without]).detailRows

        let first = try #require(rows.first { $0.key.id == "a" })
        #expect(first.tooltip.contains("Tokens: 120"))
        #expect(first.tooltip.contains("Click to return to this session"))
        #expect(!first.tooltip.contains("unknown model"))

        let second = try #require(rows.first { $0.key.id == "b" })
        #expect(second.tooltip.contains("Tokens: none reported"))
        #expect(second.tooltip.contains("OpenCode publishes no link"))
    }

    // MARK: - Diagnostics

    @Test func diagnosticLinesCarryCodesAndNoContent() {
        let canary = "VIBRA_MENU_CANARY"
        let leaky = session(
            "abcd1111", state: .awaitingInput, cwd: "/fake/\(canary)", title: canary,
            branch: canary, model: canary,
            usage: TokenUsage(input: 7, output: 3, cacheCreation: 0, cacheRead: 0))
        let snapshot = StatusSnapshot(
            sessions: [leaky],
            health: [.claudeCode: .failing(.readFailed, lastSuccess: now)],
            attention: [leaky.key: .observed(now.addingTimeInterval(-240))])

        let built = SessionMenuModel.build(snapshot, now: now)
        let lines = built.diagnosticLines(snapshot, now: now)

        #expect(lines.count == 2)
        #expect(!lines.contains { $0.contains(canary) })
        #expect(!lines.contains { $0.contains("Tokens") })

        let row = lines[0].split(separator: "\t").map(String.init)
        #expect(row == ["needsYou", "claudeCode", "abcd1111", "awaitingInput", "observed", "240", "return"])
        #expect(lines[1] == "health\tclaudeCode\treadFailed")
    }

    @Test func diagnosticLinesUseADashForASessionWithNoWaitStart() {
        let s = session("a", state: .awaitingInput)
        let snapshot = StatusSnapshot(sessions: [s], attention: [:])
        let lines = SessionMenuModel.build(snapshot, now: now).diagnosticLines(snapshot, now: now)
        let row = lines[0].split(separator: "\t").map(String.init)
        #expect(row[4] == "none")
        #expect(row[5] == "-")
    }
}
