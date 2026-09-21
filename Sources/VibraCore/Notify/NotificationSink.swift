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

    /// Removes notifications already delivered for these sessions.
    ///
    /// A "your turn" alert is only true while it is true. Once the session has
    /// moved on — you answered it, or it went away — the banner in Notification
    /// Center is stale, and without this it stayed there forever: a day of agent
    /// work left a pile of alerts that had all already been dealt with.
    func withdraw(sessionIDs: [String])
}

/// Records what it was asked to deliver and withdraw. Used by tests.
public final class RecordingNotificationSink: NotificationSink {
    public private(set) var delivered: [AttentionNotification] = []
    /// Every withdrawal, in order, as it was requested. Kept per call rather
    /// than flattened so a test can tell one withdrawal of two sessions from
    /// two withdrawals of one.
    public private(set) var withdrawn: [[String]] = []

    public init() {}

    public func deliver(_ notification: AttentionNotification) {
        delivered.append(notification)
    }

    public func withdraw(sessionIDs: [String]) {
        withdrawn.append(sessionIDs)
    }

    /// Flattened view of every session id ever withdrawn, for the common assertion.
    public var withdrawnIDs: [String] { withdrawn.flatMap { $0 } }

    public func reset() {
        delivered.removeAll()
        withdrawn.removeAll()
    }
}
