import Foundation

/// Remembers when each waiting session started waiting, and how Vibra knows.
///
/// It keeps the state of every session present in the last pass, not only the
/// waiting ones: a session Vibra watched go from working to your-turn changed
/// state in front of it, and calling that "first seen waiting" would throw away
/// the one fact the label exists to report.
public struct AttentionClock: Sendable {
    private struct Recorded: Sendable, Equatable {
        var state: SessionState
        /// Set only while the session is in an attention state.
        var start: AttentionStart?
    }

    private var recorded: [SessionKey: Recorded] = [:]

    public init() {}

    /// Folds one pass of sessions in and returns the start of every session
    /// that is waiting now. Keys absent from `sessions` are pruned, so a
    /// session that vanishes and returns is "first seen" again rather than
    /// inheriting a wait that began before it disappeared.
    public mutating func advance(
        to sessions: [Session],
        now: Date
    ) -> [SessionKey: AttentionStart] {
        var next: [SessionKey: Recorded] = [:]
        var starts: [SessionKey: AttentionStart] = [:]

        for session in sessions {
            let key = session.key
            let previous = recorded[key]
            var start: AttentionStart?

            if session.state.needsAttention {
                if let previous, previous.state == session.state, let kept = previous.start {
                    // Still waiting in the same state: the original start holds.
                    start = kept
                } else if previous == nil {
                    start = .firstSeen(now)
                } else {
                    // A recorded state differs, so Vibra saw the change itself.
                    start = .observed(now)
                }
                starts[key] = start
            }

            next[key] = Recorded(state: session.state, start: start)
        }

        recorded = next
        return starts
    }
}
