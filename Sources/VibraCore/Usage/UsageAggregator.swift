import Foundation

/// Rolls token usage and dollar cost up across sessions.
///
/// Cost is computed via `CostTable`; a session whose model is unknown has no
/// cost and contributes `0` to dollar totals (it is excluded, not estimated).
public struct UsageAggregator {
    public init() {}

    // MARK: - Cost

    /// Dollar cost of a session, or `nil` when its model is unknown.
    public func cost(for session: Session) -> Double? {
        guard let rate = CostTable.rate(for: session.model) else { return nil }
        return Self.cost(session.usage, rate: rate)
    }

    public static func cost(_ usage: TokenUsage, rate: ModelRate) -> Double {
        let perMillion = 1_000_000.0
        return Double(usage.input) / perMillion * rate.input
            + Double(usage.output) / perMillion * rate.output
            + Double(usage.cacheCreation) / perMillion * rate.cacheCreation
            + Double(usage.cacheRead) / perMillion * rate.cacheRead
    }

    /// Total dollar cost across sessions; unknown-model sessions contribute 0.
    public func totalCost(for sessions: [Session]) -> Double {
        sessions.reduce(0.0) { $0 + (cost(for: $1) ?? 0.0) }
    }

    // MARK: - Usage

    public func totalUsage(for sessions: [Session]) -> TokenUsage {
        sessions.reduce(.zero) { $0 + $1.usage }
    }

    // MARK: - Rollups

    public struct DayRollup: Equatable, Sendable {
        public let day: Date
        public let usage: TokenUsage
        public let cost: Double
    }

    public struct WeekRollup: Equatable, Sendable {
        public let weekStart: Date
        public let usage: TokenUsage
        public let cost: Double
    }

    public struct AgentRollup: Equatable, Sendable {
        public let agent: AgentKind
        public let usage: TokenUsage
        public let cost: Double
    }

    public func byDay(_ sessions: [Session], calendar: Calendar = .current) -> [DayRollup] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.lastActivity) }
            .map { day, group in
                DayRollup(day: day, usage: totalUsage(for: group), cost: totalCost(for: group))
            }
            .sorted { $0.day < $1.day }
    }

    public func byWeek(_ sessions: [Session], calendar: Calendar = .current) -> [WeekRollup] {
        Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.lastActivity)?.start
                ?? calendar.startOfDay(for: session.lastActivity)
        }
        .map { weekStart, group in
            WeekRollup(weekStart: weekStart, usage: totalUsage(for: group), cost: totalCost(for: group))
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    public func byAgent(_ sessions: [Session]) -> [AgentRollup] {
        let groups = Dictionary(grouping: sessions) { $0.agent }
        return AgentKind.allCases.compactMap { agent in
            guard let group = groups[agent], !group.isEmpty else { return nil }
            return AgentRollup(agent: agent, usage: totalUsage(for: group), cost: totalCost(for: group))
        }
    }
}
