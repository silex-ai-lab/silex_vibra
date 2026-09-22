import Foundation

/// A coding agent Vibra can observe.
///
/// Every kind here is backed by an on-disk artifact the agent already writes
/// for its own purposes. Vibra never asks an agent to change how it behaves.
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case openCode
    case cursor
    case vsCode

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        case .cursor: "Cursor"
        case .vsCode: "VS Code"
        }
    }

    /// SF Symbol used for the menu-bar row.
    public var symbolName: String {
        switch self {
        case .claudeCode: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .openCode: "cube"
        case .cursor: "cursorarrow.rays"
        case .vsCode: "curlybraces"
        }
    }
}
