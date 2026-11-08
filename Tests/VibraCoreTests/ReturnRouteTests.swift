import Foundation
import Testing
@testable import VibraCore

/// What the detail window's one return button is allowed to promise.
struct ReturnRouteTests {
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func session(_ agent: AgentKind) -> Session {
        Session(id: "s-\(agent.rawValue)", agent: agent, cwd: "/fake/proj",
                startedAt: at, lastActivity: at)
    }

    @Test func pinnedPerAgent() {
        #expect(ReturnRoute.of(session(.claudeCode)) == .attempt)
        #expect(ReturnRoute.of(session(.codex)) == .attempt)
        #expect(ReturnRoute.of(session(.cursor)) == .focusApp)
        #expect(ReturnRoute.of(session(.vsCode)) == .focusApp)
        #expect(ReturnRoute.of(session(.openCode)) == .none)
        #expect(ReturnRoute.of(session(.hermes)) == .none)
    }

    @Test func everyKnownAgentIsClassified() {
        for agent in AgentKind.allCases {
            let route = ReturnRoute.of(session(agent))
            #expect([.attempt, .focusApp, .none].contains(route), "\(agent) has no route")
        }
    }
}

/// The History window and the detail model must agree on which agents have
/// history, or the detail offers a button that opens an empty window.
struct HistoryCoverageTests {
    @Test func coversClaudeCodeCodexAndHermes() {
        #expect(HistoryCoverage.agents == [.claudeCode, .codex, .hermes])
    }
}
