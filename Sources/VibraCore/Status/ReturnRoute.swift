import Foundation

public enum ReturnRoute: Sendable, Equatable {
    /// Vibra will try to reach this session. Only the attempt shows how exact it was.
    case attempt
    /// Vibra can only bring the app window forward.
    case focusApp
    case none

    /// Which return Vibra can honestly promise. `attempt` claims only that
    /// Vibra will try: no field of `Session` proves an exact return, and an
    /// IDE-hosted Claude Code session only brings its editor forward.
    public static func of(_ session: Session) -> ReturnRoute {
        switch session.agent {
        case .claudeCode, .codex: .attempt
        case .cursor, .vsCode: .focusApp
        case .openCode, .hermes: .none
        }
    }
}
