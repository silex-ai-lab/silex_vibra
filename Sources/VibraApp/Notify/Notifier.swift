import Foundation
import UserNotifications
import VibraCore

/// Posts a "your turn" notification when a session transitions into a state
/// that needs the user's attention (`.awaitingInput` or `.blocked`).
///
/// Delivery is best-effort: this bundle is only ad-hoc signed and macOS may
/// refuse to deliver, so every failure path is treated as normal rather than
/// fatal. Never notifies twice for the same session id + state within the
/// debounce window.
public final class Notifier {
    private let center: UNUserNotificationCenter
    private let debounceInterval: TimeInterval
    private var lastNotified: [String: Date] = [:]

    public init(
        center: UNUserNotificationCenter = .current(),
        debounceInterval: TimeInterval = 60
    ) {
        self.center = center
        self.debounceInterval = debounceInterval
    }

    /// Requests notification authorization once, tolerating every failure.
    ///
    /// This bundle is ad-hoc signed rather than Developer ID signed, and
    /// notification delivery is not guaranteed for such a bundle. A refusal or
    /// an outright error here is therefore an expected outcome, not an
    /// exception: the menu bar already shows everything a notification would
    /// have said, so the app must degrade quietly rather than fail.
    public func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Deliberately ignored. There is no recovery and no user-facing
            // error worth raising for a purely additive convenience.
        }
    }

    /// Posts notifications for sessions that just transitioned INTO an
    /// attention-needing state, debounced per (session id, state).
    public func notifyIfNeeded(previous: [Session], current: [Session]) {
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Date()

        for session in current {
            guard session.state.needsAttention else { continue }

            // Only a transition into attention counts; staying blocked or
            // staying awaiting-input must not re-notify.
            let prior = previousByID[session.id]
            guard prior?.state.needsAttention != true else { continue }

            guard shouldNotify(id: session.id, state: session.state, now: now) else { continue }

            markNotified(id: session.id, state: session.state, at: now)
            postNotification(for: session)
        }
    }

    private func debounceKey(id: String, state: SessionState) -> String {
        "\(id)|\(state.rawValue)"
    }

    private func shouldNotify(id: String, state: SessionState, now: Date) -> Bool {
        guard let last = lastNotified[debounceKey(id: id, state: state)] else { return true }
        return now.timeIntervalSince(last) >= debounceInterval
    }

    private func markNotified(id: String, state: SessionState, at now: Date) {
        lastNotified[debounceKey(id: id, state: state)] = now
    }

    private func postNotification(for session: Session) {
        let content = UNMutableNotificationContent()
        content.title = "vibra"
        content.body = "\(session.projectName) is waiting for you"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        // Best-effort: a denied or unavailable notification center just drops
        // this. There is nothing to recover, so the error is ignored on purpose.
        center.add(request) { _ in }
    }
}
