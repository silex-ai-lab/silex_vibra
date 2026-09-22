import Foundation

/// One observed agent session, normalized across all three sources.
///
/// `id` is the agent's own session identifier, not something Vibra invents, so
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

    /// How the agent was started, as the agent records it (Claude Code's
    /// `entrypoint`: "cli", "claude-desktop", "sdk-cli", ...). Nil when the
    /// source does not say.
    public var entrypoint: String?

    /// The Claude desktop app's id for this session (`local_...`), when it is
    /// a Claude UI session. Such a session opens in the app by deep link, with
    /// or without a running process.
    public var desktopSessionID: String?

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
        scheduledTask: String? = nil,
        entrypoint: String? = nil,
        desktopSessionID: String? = nil
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
        self.entrypoint = entrypoint
        self.desktopSessionID = desktopSessionID
    }

    /// Last path component of `cwd` - what the user actually recognizes.
    ///
    /// An editor chat with no folder open has an empty `cwd`, and resolving
    /// that as a path names whatever directory Vibra happens to run in.
    public var projectName: String {
        cwd.isEmpty ? "(no folder)" : URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Started with nobody at the keyboard: a scheduled task run, a headless
    /// `claude -p` / SDK run (entrypoint "sdk-cli"), or a `codex exec` run
    /// (originator "codex_exec"), such as a launchd or agent-fleet job.
    /// Finishing its turn is the job being done, not a question for anyone.
    public var isUnattended: Bool {
        scheduledTask != nil || entrypoint == "sdk-cli" || entrypoint == "codex_exec"
    }

    /// Whether this session's current state is worth a notification.
    ///
    /// "Needs approval" always is: even an unattended job is stuck until
    /// someone answers the prompt. "Your turn" is not, for an unattended job -
    /// no one is expected to reply, so an hourly job's every run ended in an
    /// alert that asked for nothing.
    public var wantsNotification: Bool {
        switch state {
        case .blocked: return true
        case .awaitingInput: return !isUnattended
        default: return false
        }
    }

    /// What to call the session: its Claude UI title when it has one, else the
    /// project folder.
    public var displayName: String {
        title ?? projectName
    }

    /// Applies what the Claude desktop app and Claude Code's live status files
    /// know, and drops sessions archived in the Claude UI.
    ///
    /// - A Claude UI session gets its sidebar title and its desktop id.
    /// - A running Claude session's own status overrides the transcript
    ///   inference: `waiting` is blocked on the user (a permission prompt
    ///   leaves no trace in the transcript), `busy` is working.
    public static func enriched(
        _ sessions: [Session],
        desktop: [String: DesktopSessionInfo],
        live: [String: ClaudeLiveStatus]
    ) -> [Session] {
        sessions.compactMap { session in
            guard session.agent == .claudeCode else { return session }
            var s = session
            if let info = desktop[s.id] {
                if info.isArchived { return nil }
                s.desktopSessionID = info.localID
                if let title = info.title { s.title = title }
            }
            switch live[s.id]?.status {
            case "waiting": s.state = .blocked
            case "busy": s.state = .working
            default: break
            }
            return s
        }
    }

    /// Drops sessions whose process is known to have exited.
    ///
    /// `live` maps an agent to the ids that still have a process; an agent
    /// absent from it cannot tell (OpenCode publishes no link) and keeps every
    /// session. A Claude UI session is kept while it is open in the app. A
    /// session working right now is kept regardless - output in the
    /// last few seconds is proof enough of life, and a headless run that writes
    /// no session file must not vanish mid-job.
    public static func withoutExited(
        _ sessions: [Session],
        live: [AgentKind: Set<String>]
    ) -> [Session] {
        sessions.filter { session in
            guard let ids = live[session.agent] else { return true }
            if session.state == .working || ids.contains(session.id) { return true }
            // A Claude UI session outlives its process: the desktop app parks
            // it when quiet and respawns it on the next message, and it opens
            // by deep link either way. Unattended runs are the exception -
            // a finished scheduled run is done, not parked.
            return session.desktopSessionID != nil && !session.isUnattended
        }
    }

    /// Bundle id of the editor app this session lives inside, for agents that
    /// run in an editor window rather than in a process of their own.
    public var editorBundleID: String? {
        switch agent {
        case .vsCode:
            entrypoint == "vscode-insiders" ? "com.microsoft.VSCodeInsiders" : "com.microsoft.VSCode"
        case .cursor:
            "com.todesktop.230313mzl4w4u92"
        default:
            nil
        }
    }

    /// Settles editor-hosted sessions whose editor is gone.
    ///
    /// VS Code stops a pending reply when it quits (it asks first), but leaves
    /// the log saying "waiting for confirmation" or "in progress", and does not
    /// correct it on relaunch. Read literally, that is a chat stuck on
    /// "needs approval" for hours. A reply can only be live inside the editor
    /// process that is running now, so a working, blocked or stalled session
    /// is idle when its editor is not running, or when nothing has happened in
    /// it since that editor launched.
    ///
    /// Cursor also leaves a turn you stopped looking exactly like one still
    /// running (status "aborted"), so for Cursor a stall - minutes of silence
    /// mid-turn - is read as a stopped turn: idle, not a warning.
    ///
    /// `editorLaunch` maps a bundle id to the launch time of its running copy;
    /// an editor absent from it is not running.
    public static func settlingOrphaned(_ sessions: [Session], editorLaunch: [String: Date]) -> [Session] {
        sessions.map { session in
            guard let bundleID = session.editorBundleID,
                  [.working, .blocked, .stalled].contains(session.state)
            else { return session }
            if session.agent == .cursor, session.state == .stalled {
                var settled = session
                settled.state = .idle
                return settled
            }
            if let launched = editorLaunch[bundleID], session.lastActivity >= launched {
                return session
            }
            var settled = session
            settled.state = .idle
            return settled
        }
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
