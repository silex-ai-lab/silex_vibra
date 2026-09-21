import Foundation

/// A finished report over a rolling window.
///
/// Dollar figures are an **estimated API-equivalent value** computed locally
/// from token counts times published rates. They are not a bill: on a
/// subscription you pay a flat fee, and these numbers say what the same usage
/// would have cost at list price. Nothing in producing this report leaves the
/// machine.
public struct UsageReport: Sendable, Equatable {

    public struct DayLine: Sendable, Equatable {
        public let day: Date
        public let usage: TokenUsage
        public let estimatedValue: Double
        /// Tokens that could not be priced because their model has no known
        /// published rate. Reported separately so an unpriced day never looks
        /// like a free one.
        public let unpricedTokens: Int
    }

    public struct AgentLine: Sendable, Equatable {
        public let agent: AgentKind
        public let usage: TokenUsage
        public let estimatedValue: Double
        public let unpricedTokens: Int
    }

    public let windowDays: Int
    public let generatedAt: Date
    /// Oldest local day included, inclusive.
    public let windowStart: Date

    public let days: [DayLine]
    public let agents: [AgentLine]

    public let total: TokenUsage
    public let estimatedValue: Double
    public let unpricedTokens: Int

    /// Usage that is real but carries no timestamp, so it cannot be placed on
    /// a day. Shown on its own line rather than silently folded into today.
    public let undated: TokenUsage
    public let undatedEstimatedValue: Double

    public var hasUnpriced: Bool { unpricedTokens > 0 }
}
