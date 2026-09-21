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

    /// What the adapter last saw happen. Feeds `StateEngine`, which owns the
    /// recency rules so all three adapters classify identically.
    /// Defaults to `.unknown` so an adapter that cannot tell still compiles.
    public var lastEvent: LastEventKind

    /// Name of the scheduled task that started this session, when it was one.
    /// A scheduled task starts a brand-new session on every run, so this is
    /// the only thing linking an hourly job's runs to each other.
    public var scheduledTask: String?

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
        title: String? = nil,
        lastEvent: LastEventKind = .unknown,
        scheduledTask: String? = nil
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
        self.lastEvent = lastEvent
        self.scheduledTask = scheduledTask
    }

    /// Last path component of `cwd` - what the user actually recognizes.
    public var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// What a notification for this session is keyed by. Every run of one
    /// scheduled task shares a key, so a new run replaces the previous run's
    /// notification instead of stacking beside it; anything else is keyed by
    /// its own session.
    public var notificationKey: String {
        if let scheduledTask { return "scheduled-task:\(scheduledTask)" }
        return id
    }
}
