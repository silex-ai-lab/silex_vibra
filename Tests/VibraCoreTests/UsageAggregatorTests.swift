import Foundation
import Testing
@testable import VibraCore

struct UsageAggregatorTests {
    private func session(
        agent: AgentKind = .claudeCode,
        model: String,
        lastActivity: Date = Date(),
        input: Int,
        output: Int,
        cacheCreation: Int,
        cacheRead: Int
    ) -> Session {
        Session(
            id: UUID().uuidString,
            agent: agent,
            cwd: "/Users/demo/workplace/sample",
            model: model,
            state: .idle,
            startedAt: lastActivity,
            lastActivity: lastActivity,
            usage: TokenUsage(input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead)
        )
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func dollarTotalToFourDecimals() {
        let sessions = [
            session(model: "claude-opus-5", input: 1_000_000, output: 2_000_000, cacheCreation: 0, cacheRead: 1_000_000),
        ]
        // 15.00 + 150.00 + 1.50 = 166.50
        let total = UsageAggregator().totalCost(for: sessions)
        #expect(abs(total - 166.50) < 0.0001)
    }

    @Test func cacheAwareCost() {
        let sessions = [
            session(model: "claude-sonnet-5", input: 1_000_000, output: 0, cacheCreation: 1_000_000, cacheRead: 1_000_000),
        ]
        // 3.00 input + 3.75 cache write + 0.30 cache read = 7.05
        let total = UsageAggregator().totalCost(for: sessions)
        #expect(abs(total - 7.05) < 0.0001)
    }

    @Test func unknownModelIsNeverGuessed() {
        let unknown = session(model: "made-up-model", input: 1_000_000, output: 1_000_000, cacheCreation: 0, cacheRead: 0)
        let aggregator = UsageAggregator()
        #expect(aggregator.cost(for: unknown) == nil)
        #expect(aggregator.totalCost(for: [unknown]) == 0.0)
    }

    @Test func dayAndWeekAndAgentRollups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let day1 = utcDate(2026, 9, 19)
        let day2 = utcDate(2026, 9, 26)

        let a = session(agent: .claudeCode, model: "claude-opus-5", lastActivity: day1, input: 100, output: 0, cacheCreation: 0, cacheRead: 0)
        let b = session(agent: .claudeCode, model: "claude-opus-5", lastActivity: day1.addingTimeInterval(60), input: 200, output: 0, cacheCreation: 0, cacheRead: 0)
        let c = session(agent: .codex, model: "gpt-5.6", lastActivity: day2, input: 300, output: 0, cacheCreation: 0, cacheRead: 0)

        let aggregator = UsageAggregator()
        let all = [a, b, c]

        let days = aggregator.byDay(all, calendar: calendar)
        #expect(days.count == 2)
        #expect(days[0].usage.input == 300)
        #expect(days[1].usage.input == 300)

        let weeks = aggregator.byWeek(all, calendar: calendar)
        #expect(weeks.count == 2)

        let agents = aggregator.byAgent(all)
        #expect(agents.count == 2)
        #expect(agents.first { $0.agent == .claudeCode }?.usage.input == 300)
        #expect(agents.first { $0.agent == .codex }?.usage.input == 300)
    }
}
