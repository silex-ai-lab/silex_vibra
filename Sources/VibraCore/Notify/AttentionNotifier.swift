import Foundation

/// Decides when a session deserves a "your turn" notification, and when an
/// already-delivered one has stopped being true.
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
/// The mirror of rule 1 is withdrawal: a session that *leaves* an attention
/// state, or disappears entirely, has its notification pulled. Without it a
/// banner outlived the condition it described — you answered the agent, it went
/// back to work, and the alert stayed in Notification Center regardless.
///
/// Notifications are keyed by `Session.notificationKey`, not session id. A
/// scheduled task starts a new session every run, and keying by session made an
/// hourly job pile up one notification per run. Keyed by task, each run
/// replaces the last and only the latest is ever shown.
///
/// Holds no system dependency and takes its clock as a parameter, so the rules
/// can be tested without a signed bundle, user authorization, or waiting a
/// real minute for the debounce to expire.
public final class AttentionNotifier {
    private let sink: any NotificationSink
    private let debounceInterval: TimeInterval
    private var lastNotified: [String: Date] = [:]
    /// Notifications currently sitting in Notification Center: key -> the
    /// session the latest delivery under that key was about. Only that session
    /// resolving withdraws it - an older run of the same task resolving must
    /// not pull the notification a newer run replaced it with.
    private var outstanding: [String: String] = [:]

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
            outstanding[session.notificationKey] = session.id

            let label = session.scheduledTask.map { "\($0) (\(session.projectName))" }
                ?? session.projectName
            sink.deliver(
                AttentionNotification(
                    key: session.notificationKey,
                    sessionID: session.id,
                    title: "vibra",
                    body: "\(label) is waiting for you"
                )
            )
        }

        withdrawResolved(current: current)
    }

    /// Pulls notifications whose condition no longer holds.
    ///
    /// Two ways that happens, and both are stale in the same way: the session is
    /// still here but no longer needs you, or it is gone from the snapshot
    /// entirely (the agent exited, or it aged out of the activity window).
    private func withdrawResolved(current: [Session]) {
        guard !outstanding.isEmpty else { return }

        let stillNeedsAttention = Set(
            current.filter { $0.state.needsAttention }.map(\.id)
        )
        let resolved = outstanding
            .filter { !stillNeedsAttention.contains($0.value) }
            .map(\.key)
        guard !resolved.isEmpty else { return }

        for key in resolved { outstanding.removeValue(forKey: key) }

        // Sorted so the call is deterministic — it is otherwise dictionary
        // order, which makes a test that asserts on it flaky rather than wrong.
        sink.withdraw(keys: resolved.sorted())

        // Prune debounce entries for sessions that vanished, so the dictionary
        // stays bounded over a long-running day. Entries for sessions that are
        // merely resolved stay: the debounce exists for state flicker, and
        // clearing it would let a flickering session re-alert immediately, which
        // is exactly what rule 2 is there to prevent.
        let presentIDs = Set(current.map(\.id))
        for key in lastNotified.keys where !presentIDs.contains(sessionID(fromKey: key)) {
            lastNotified.removeValue(forKey: key)
        }
    }

    /// The debounce key is "<session id>|<state>"; the id may itself contain "|",
    /// so split from the right.
    private func sessionID(fromKey key: String) -> String {
        guard let sep = key.lastIndex(of: "|") else { return key }
        return String(key[key.startIndex..<sep])
    }

    /// Withdraws one session's notification because the user acted on it —
    /// clicked it and was taken to the session's terminal.
    ///
    /// The session may well still need attention (you have only just arrived at
    /// the prompt), so waiting for `withdrawResolved` would leave the banner
    /// sitting there after it has done its job. The debounce entry is kept, for
    /// the same reason as on ordinary withdrawal.
    ///
    /// Matches on the session, not the key: clicking an older run's
    /// notification that has since been replaced is not a reason to pull the
    /// newer one.
    public func dismiss(sessionID: String) {
        guard let key = outstanding.first(where: { $0.value == sessionID })?.key
        else { return }
        outstanding.removeValue(forKey: key)
        sink.withdraw(keys: [key])
    }

    /// Sessions whose notification is currently showing, sorted. One per key:
    /// an older run of a scheduled task whose notification a newer run
    /// replaced is not listed.
    public var outstandingSessionIDs: [String] {
        outstanding.values.sorted()
    }

    /// Withdraws everything still outstanding. Used when the app is going away:
    /// a "waiting for you" banner that outlives the process it came from can no
    /// longer be acted on from the menu bar, so it is pure noise.
    public func withdrawAll() {
        guard !outstanding.isEmpty else { return }
        sink.withdraw(keys: outstanding.keys.sorted())
        outstanding.removeAll()
    }
}
