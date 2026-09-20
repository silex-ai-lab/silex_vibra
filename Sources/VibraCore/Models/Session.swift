import Foundation

/// One observed agent session, normalized across all three sources.
///
/// `id` is the agent's own session identifier, not something vibra invents, so
/// a session keeps its identity across restarts of the monitor.
public struct Session: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let agent: AgentKind

    /// Working directory the session was launched in. Used for the display
    /// label and for the terminal-jump lookup.
    public var cwd: String
    public var gitBranch: String?
    public var model: String?

    public var state: SessionState
    public var startedAt: Date
    public var lastActivity: Date
    public var usage: TokenUsage

    /// Short human label, when the source provides one.
    public var title: String?

    public init(
        id: String,
        agent: AgentKind,
        cwd: String,
        gitBranch: String? = nil,
        model: String? = nil,
        state: SessionState = .idle,
        startedAt: Date,
        lastActivity: Date,
        usage: TokenUsage = .zero,
        title: String? = nil
    ) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.model = model
        self.state = state
        self.startedAt = startedAt
        self.lastActivity = lastActivity
        self.usage = usage
        self.title = title
    }

    /// Last path component of `cwd` - what the user actually recognizes.
    public var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}
