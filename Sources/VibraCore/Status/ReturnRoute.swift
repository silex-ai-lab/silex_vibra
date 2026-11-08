import Foundation

public enum ReturnRoute: Sendable, Equatable {
    /// Vibra will try to reach this session. Only the attempt shows how exact it was.
    case attempt
    /// Vibra can only bring the app window forward.
    case focusApp
    case none

    public static func of(_ session: Session) -> ReturnRoute {
        .none
    }
}
