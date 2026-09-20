import Foundation

/// What a session is doing right now.
///
/// The distinction that matters to a user is `working` (leave it alone) versus
/// `awaitingInput` (it wants you). `stalled` exists because an agent that died
/// mid-turn looks identical to a busy one if you only check "is it working".
public enum SessionState: String, Codable, Sendable, CaseIterable {
    /// The agent is producing output.
    case working
    /// The agent asked something and is waiting on the human.
    case awaitingInput
    /// Settled, turn complete, nothing pending.
    case idle
    /// Was working, then went quiet for longer than the stall threshold.
    case stalled
    /// Sitting on a permission or approval dialog.
    case blocked

    /// True when the user's attention is the thing holding this session up.
    public var needsAttention: Bool {
        self == .awaitingInput || self == .blocked
    }
}
