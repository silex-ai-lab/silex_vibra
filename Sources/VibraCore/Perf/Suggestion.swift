import Foundation

/// One fired perf pattern in one Claude Code session. Typed evidence only:
/// every string the user reads is built by the report's text renderer, so a
/// suggestion can be compared, encoded and tested without any wording.
public struct Suggestion: Sendable, Equatable, Codable {
    /// Why a cache rewrite happened, as far as the transcript can say. A
    /// correlation, never a proven cause.
    public enum RewriteCause: String, Sendable, Codable {
        case modelSwitch, idleOver1h, idleOver5m, other
    }

    public enum Finding: Sendable, Equatable, Codable {
        case contextCarry(segments: Int, turnsAboveFloor: Int, peakContext: Int, floorTokens: Int)
        case cacheRewrite(events: Int, rewrittenTokens: Int, dominantCause: RewriteCause)
        case explorationBurst(bursts: Int, burstTurns: Int)
    }

    /// Transcript file name without extension.
    public let sessionID: String
    /// First non-nil `project` among the session's turns, else "".
    public let project: String
    /// Timestamp of the session's first in-window turn.
    public let startedAt: Date?
    /// In-window turns.
    public let turns: Int
    public let finding: Finding
    /// Nil when the session is unpriced.
    public let exposureUSD: Double?
    /// Nil when the session is unpriced.
    public let sessionValueUSD: Double?
    public let isLead: Bool

    public init(
        sessionID: String,
        project: String,
        startedAt: Date?,
        turns: Int,
        finding: Finding,
        exposureUSD: Double?,
        sessionValueUSD: Double?,
        isLead: Bool
    ) {
        self.sessionID = sessionID
        self.project = project
        self.startedAt = startedAt
        self.turns = turns
        self.finding = finding
        self.exposureUSD = exposureUSD
        self.sessionValueUSD = sessionValueUSD
        self.isLead = isLead
    }
}

public struct PerfReport: Sendable, Equatable, Codable {
    /// The values the analyzer used.
    public let thresholds: PerfThresholds
    public let analyzedSessions: Int
    public let unpricedSessions: Int
    public let skippedSmallSessions: Int
    /// Every fired suggestion, ordered by `Finding` case name, then `sessionID`.
    public let suggestions: [Suggestion]

    public init(
        thresholds: PerfThresholds,
        analyzedSessions: Int,
        unpricedSessions: Int,
        skippedSmallSessions: Int,
        suggestions: [Suggestion]
    ) {
        self.thresholds = thresholds
        self.analyzedSessions = analyzedSessions
        self.unpricedSessions = unpricedSessions
        self.skippedSmallSessions = skippedSmallSessions
        self.suggestions = suggestions
    }
}
