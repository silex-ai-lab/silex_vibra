import Foundation

/// One timestamped, attributable slice of token usage.
///
/// Adapters emit these while folding records. The point is that usage is
/// attributed at the moment it was *incurred*, not to the session that
/// contains it: a session spanning 2026-09-18 to 09-21 carrying 145M tokens
/// would otherwise dump its entire total — and its entire dollar value — onto
/// its last day, showing zero for the three days the work actually happened.
public struct UsageSample: Sendable, Equatable {
    /// When this usage was incurred. Nil when the source cannot say — the
    /// OpenCode database stores per-session totals with no per-record
    /// timestamps, so its usage is real but undatable.
    public let timestamp: Date?

    /// Model that incurred it. Nil when unknown. Kept per sample because a
    /// session can switch models mid-flight, and pricing the whole session at
    /// whichever model happened to be last is simply wrong.
    public let model: String?

    /// The delta incurred at this point — never a running total.
    public let usage: TokenUsage

    public init(timestamp: Date?, model: String?, usage: TokenUsage) {
        self.timestamp = timestamp
        self.model = model
        self.usage = usage
    }
}

/// Bucket identity for report aggregation.
public struct UsageBucket: Hashable, Sendable {
    /// Start of the *local* day this usage belongs to. Nil means undatable.
    ///
    /// Local, not UTC: transcript timestamps are UTC, and bucketing by UTC day
    /// silently moves an evening session into the next day.
    public let day: Date?
    public let model: String?

    public init(day: Date?, model: String?) {
        self.day = day
        self.model = model
    }
}
