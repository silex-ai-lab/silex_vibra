import Foundation

/// Turns timestamped usage samples into a rolling-window report.
///
/// All the error-prone accounting lives here, in one testable place:
///
/// - Buckets are **local** days. Transcript timestamps are UTC; bucketing by
///   UTC day silently moves an evening session into tomorrow.
/// - The window filter is applied **per day, not per session**. A session
///   active today whose earlier days fall outside the window must contribute
///   only its in-window days.
/// - Pricing is per `(day, model)`. A session that switched models mid-flight
///   must not have its whole total priced at whichever model happened to be
///   last.
/// - An unknown model yields *unpriced tokens*, never a zero dollar figure.
///   Free and unknown must not look the same.
public struct ReportBuilder: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func build(
        samplesByAgent: [AgentKind: [UsageSample]],
        now: Date = Date(),
        windowDays: Int = 7
    ) -> UsageReport {
        let today = calendar.startOfDay(for: now)
        // A 7-day window is today plus the six preceding days.
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today

        var perAgent: [AgentKind: [UsageBucket: TokenUsage]] = [:]
        var undated = TokenUsage.zero

        for (agent, samples) in samplesByAgent {
            var buckets: [UsageBucket: TokenUsage] = [:]
            for sample in samples {
                guard let timestamp = sample.timestamp else {
                    // Undatable usage is kept, but never attributed to a day.
                    undated += sample.usage
                    continue
                }
                let day = calendar.startOfDay(for: timestamp)
                // Per-day window filter, not per-session.
                guard day >= windowStart, day <= today else { continue }
                let key = UsageBucket(day: day, model: sample.model)
                buckets[key, default: .zero] += sample.usage
            }
            if !buckets.isEmpty { perAgent[agent] = buckets }
        }

        // Day lines
        var byDay: [Date: (usage: TokenUsage, value: Double, unpriced: Int)] = [:]
        var agentLines: [UsageReport.AgentLine] = []
        var total = TokenUsage.zero
        var totalValue = 0.0
        var totalUnpriced = 0

        for agent in AgentKind.allCases {
            guard let buckets = perAgent[agent] else { continue }
            var agentUsage = TokenUsage.zero
            var agentValue = 0.0
            var agentUnpriced = 0

            for (key, usage) in buckets {
                agentUsage += usage
                let priced = price(usage: usage, model: key.model)
                agentValue += priced.value
                agentUnpriced += priced.unpricedTokens

                if let day = key.day {
                    var entry = byDay[day] ?? (.zero, 0, 0)
                    entry.usage += usage
                    entry.value += priced.value
                    entry.unpriced += priced.unpricedTokens
                    byDay[day] = entry
                }
            }

            agentLines.append(
                UsageReport.AgentLine(
                    agent: agent,
                    usage: agentUsage,
                    estimatedValue: agentValue,
                    unpricedTokens: agentUnpriced
                )
            )
            total += agentUsage
            totalValue += agentValue
            totalUnpriced += agentUnpriced
        }

        let dayLines = byDay
            .map {
                UsageReport.DayLine(
                    day: $0.key,
                    usage: $0.value.usage,
                    estimatedValue: $0.value.value,
                    unpricedTokens: $0.value.unpriced
                )
            }
            .sorted { $0.day < $1.day }

        let undatedPriced = price(usage: undated, model: nil)

        return UsageReport(
            windowDays: windowDays,
            generatedAt: now,
            windowStart: windowStart,
            days: dayLines,
            agents: agentLines,
            total: total,
            estimatedValue: totalValue,
            unpricedTokens: totalUnpriced,
            undated: undated,
            undatedEstimatedValue: undatedPriced.value
        )
    }

    /// Prices one bucket. An unknown model contributes no dollars and all of
    /// its tokens to `unpricedTokens`, so the UI can say "plus N unpriced
    /// tokens" instead of implying they were free.
    private func price(usage: TokenUsage, model: String?) -> (value: Double, unpricedTokens: Int) {
        guard usage.total > 0 else { return (0, 0) }
        guard let rate = CostTable.rate(for: model) else {
            return (0, usage.total)
        }
        return (UsageAggregator.cost(usage, rate: rate), 0)
    }
}
