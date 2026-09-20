import Foundation

/// The last thing an adapter saw happen in a session.
///
/// Adapters map their own record types onto this small vocabulary so the
/// classification rules live in exactly one place instead of being reinvented
/// three times with three slightly different notions of "busy".
public enum LastEventKind: String, Codable, Sendable {
    /// Agent emitted output and intends to continue (e.g. stop_reason tool_use).
    case producing
    /// Agent finished its turn. The ball is in the human's court.
    case turnComplete
    /// Agent is sitting on a permission / approval prompt.
    case permissionPrompt
    /// Nothing recognizable.
    case unknown
}

/// Thresholds for turning "when did something last happen" into a state.
public struct StateEngineConfig: Sendable, Equatable {
    /// Activity newer than this means the session is actively producing.
    public var workingWindow: TimeInterval
    /// A producing session quiet for longer than this is presumed stalled.
    public var stallThreshold: TimeInterval
    /// A completed session untouched for longer than this drops to idle, so a
    /// finished session from yesterday stops claiming your attention forever.
    public var attentionDecay: TimeInterval

    public init(
        workingWindow: TimeInterval = 30,
        stallThreshold: TimeInterval = 300,
        attentionDecay: TimeInterval = 8 * 3600
    ) {
        self.workingWindow = workingWindow
        self.stallThreshold = stallThreshold
        self.attentionDecay = attentionDecay
    }

    public static let `default` = StateEngineConfig()
}

/// Turns (last event, last activity time) into a `SessionState`.
///
/// Deliberately a pure function of its inputs: no clock of its own, no I/O.
/// `now` is injected so the rules can be tested without sleeping.
public struct StateEngine: Sendable {
    public let config: StateEngineConfig

    public init(config: StateEngineConfig = .default) {
        self.config = config
    }

    public func classify(
        lastEvent: LastEventKind,
        lastActivity: Date,
        now: Date = Date()
    ) -> SessionState {
        let quiet = now.timeIntervalSince(lastActivity)

        switch lastEvent {
        case .permissionPrompt:
            // A permission prompt does not expire on its own. It is blocking
            // until something changes it, however long that takes.
            return .blocked

        case .turnComplete:
            // The agent is done and waiting on the human - but only call that
            // "your turn" while it is still plausibly live. A finished session
            // from this morning is idle, not an unanswered question.
            return quiet <= config.attentionDecay ? .awaitingInput : .idle

        case .producing:
            if quiet <= config.workingWindow { return .working }
            if quiet <= config.stallThreshold { return .working }
            // Claimed to be mid-turn, then went silent. This is the case a
            // naive "is it running?" check reports as healthy forever.
            return .stalled

        case .unknown:
            return quiet <= config.workingWindow ? .working : .idle
        }
    }
}
