import Foundation

/// Decides when a session deserves a "your turn" notification.
///
/// Two rules, and both matter:
///
/// 1. Only a *transition* into an attention state notifies. A session that was
///    already waiting and is still waiting must stay quiet, or every refresh
///    would re-alert for the same unanswered prompt.
/// 2. The same (session, state) is debounced. A session that flickers between
///    states — which happens when an agent writes several records in quick
///    succession — must not produce a burst.
///
/// Holds no system dependency and takes its clock as a parameter, so the rules
/// can be tested without a signed bundle, user authorization, or waiting a
/// real minute for the debounce to expire.
public final class AttentionNotifier {
    private let sink: any NotificationSink
    private let debounceInterval: TimeInterval
    private var lastNotified: [String: Date] = [:]

    public init(sink: any NotificationSink, debounceInterval: TimeInterval = 60) {
        self.sink = sink
        self.debounceInterval = debounceInterval
    }

    /// Delivers for sessions that just entered an attention-needing state.
    ///
    /// `now` is injected rather than read from the clock so debounce behaviour
    /// is deterministic in tests.
    public func notifyIfNeeded(
        previous: [Session],
        current: [Session],
        now: Date = Date()
    ) {
        let previousByID = Dictionary(
            previous.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for session in current {
            guard session.state.needsAttention else { continue }

            // Rule 1: staying in an attention state is not a transition.
            if previousByID[session.id]?.state.needsAttention == true { continue }

            // Rule 2: debounce per (session, state).
            let key = "\(session.id)|\(session.state.rawValue)"
            if let last = lastNotified[key],
               now.timeIntervalSince(last) < debounceInterval {
                continue
            }
            lastNotified[key] = now

            sink.deliver(
                AttentionNotification(
                    sessionID: session.id,
                    title: "vibra",
                    body: "\(session.projectName) is waiting for you"
                )
            )
        }
    }
}
