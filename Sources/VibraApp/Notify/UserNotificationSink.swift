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

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
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

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }
}
