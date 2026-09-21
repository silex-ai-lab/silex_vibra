import Foundation
import UserNotifications
import VibraCore

/// Delivers via macOS notification center.
///
/// Deliberately thin: it contains no decisions, only delivery. Everything
/// worth testing — transition detection and debounce — lives in
/// `AttentionNotifier` in VibraCore, because this class cannot be exercised
/// from a test. It needs a signed bundle and user authorization, and silently
/// drops anything it is not allowed to show.
final class UserNotificationSink: NotificationSink {
    private let center: UNUserNotificationCenter
    /// Held strongly: `UNUserNotificationCenter.delegate` is weak.
    private var clickHandler: ClickHandler?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Calls `handler` with the session id when the user clicks one of vibra's
    /// notifications. Without a delegate a click only activates vibra, which has
    /// no window, so it looked like nothing happened.
    func onClick(_ handler: @escaping @MainActor @Sendable (String) -> Void) {
        let clickHandler = ClickHandler(onClick: handler)
        self.clickHandler = clickHandler
        center.delegate = clickHandler
    }

    /// Requests authorization once, tolerating every failure.
    ///
    /// An ad-hoc signed bundle is refused outright by macOS
    /// ("Notifications are not allowed for this application"), so a refusal
    /// here is an expected outcome rather than an error. The menu bar already
    /// shows everything a notification would say.
    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Ignored on purpose: nothing to recover, nothing worth surfacing.
        }
    }

    func deliver(_ notification: AttentionNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body

        // Keyed by session, not by UUID. Two reasons, and the first is the one
        // that was broken: a random id per delivery leaves nothing to withdraw
        // by, so a resolved alert could never be pulled. The second is that
        // macOS replaces a delivered notification that reuses an identifier, so
        // one session repeatedly wanting you coalesces into one entry instead
        // of stacking.
        let request = UNNotificationRequest(
            identifier: notification.sessionID,
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }

    func withdraw(sessionIDs: [String]) {
        guard !sessionIDs.isEmpty else { return }
        // Delivered only: a pending request would be one scheduled for later,
        // and vibra never schedules — every notification is posted immediately
        // with a nil trigger.
        center.removeDeliveredNotifications(withIdentifiers: sessionIDs)
    }
}

/// Separate from the sink so it can be `Sendable`: the notification center
/// calls its delegate off the main thread, and this holds nothing mutable.
private final class ClickHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let onClick: @MainActor @Sendable (String) -> Void

    init(onClick: @escaping @MainActor @Sendable (String) -> Void) {
        self.onClick = onClick
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Only a click on the body. Dismissing it from Notification Center is
        // not a request to be taken anywhere.
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // The request identifier is the session id - see `deliver`.
            let sessionID = response.notification.request.identifier
            let onClick = self.onClick
            Task { @MainActor in onClick(sessionID) }
        }
        completionHandler()
    }
}
