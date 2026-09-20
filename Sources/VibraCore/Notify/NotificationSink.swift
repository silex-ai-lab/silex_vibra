import Foundation

/// One notification vibra wants delivered.
public struct AttentionNotification: Equatable, Sendable {
    public let sessionID: String
    public let title: String
    public let body: String

    public init(sessionID: String, title: String, body: String) {
        self.sessionID = sessionID
        self.title = title
        self.body = body
    }
}

/// Somewhere a notification can be delivered.
///
/// Exists so the decision logic can be tested without the system notification
/// center, which cannot be driven from a test: it needs a signed bundle, user
/// authorization, and it swallows everything it refuses. The interesting part
/// of this feature is *when* we notify, and that is now testable on its own.
public protocol NotificationSink: AnyObject {
    func deliver(_ notification: AttentionNotification)
}

/// Records what it was asked to deliver. Used by tests.
public final class RecordingNotificationSink: NotificationSink {
    public private(set) var delivered: [AttentionNotification] = []

    public init() {}

    public func deliver(_ notification: AttentionNotification) {
        delivered.append(notification)
    }

    public func reset() { delivered.removeAll() }
}
