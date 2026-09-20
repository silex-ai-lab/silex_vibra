import Foundation

/// A coding agent vibra can observe.
///
/// Every kind here is backed by an on-disk artifact the agent already writes
/// for its own purposes. vibra never asks an agent to change how it behaves.
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case openCode

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        }
    }

    /// SF Symbol used for the menu-bar row.
    public var symbolName: String {
        switch self {
        case .claudeCode: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .openCode: "cube"
        }
    }
}
