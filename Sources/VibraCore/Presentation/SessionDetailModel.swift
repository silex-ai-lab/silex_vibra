import Foundation

public struct SessionDetailModel: Sendable, Equatable {
    public let heading: String
    public let agentName: String
    public let branch: String
    public let stateLine: String
    public let evidenceLine: String
    public let lastObservedLine: String
    public let healthLine: String
    public let tokensLine: String
    public let cwd: String
    public let returnRoute: ReturnRoute
    public let isLive: Bool
    public let historyAvailable: Bool
    public let evidenceAvailable: Bool

    public static func build(
        session: Session,
        snapshot: StatusSnapshot,
        now: Date
    ) -> SessionDetailModel {
        let isLive = snapshot.sessions.contains { $0.key == session.key }
        let start = snapshot.attention[session.key]

        return SessionDetailModel(
            heading: session.displayName,
            agentName: session.agent.displayName,
            branch: session.gitBranch ?? "Not reported",
            stateLine: isLive
                ? stateText(session, start: start, now: now)
                : "No longer active",
            evidenceLine: evidenceLine(session),
            lastObservedLine: "Last activity "
                + "\(formatDuration(now.timeIntervalSince(session.lastActivity))) ago",
            healthLine: healthLine(session.agent, snapshot.health[session.agent], now),
            tokensLine: session.usage.total > 0 ? "\(session.usage.total) tokens" : "None reported",
            cwd: session.cwd,
            returnRoute: ReturnRoute.of(session),
            isLive: isLive,
            historyAvailable: HistoryCoverage.agents.contains(session.agent),
            evidenceAvailable: EvidenceCoverage.agents.contains(session.agent)
        )
    }

    /// What the session's last record means, in words that do not claim more
    /// than the record proves. A finished turn is not a finished task.
    private static func evidenceLine(_ session: Session) -> String {
        switch session.lastEvent {
        case .permissionPrompt:
            return "Observed a permission prompt in the session."
        case .turnComplete:
            return "The agent's last turn ended; waiting for you to reply is inferred from that."
        case .producing:
            return session.state == .stalled
                ? "The agent was mid-turn and has written nothing since."
                : "The agent wrote output recently."
        case .settled:
            return "The session reported it had finished."
        case .unknown:
            return "Vibra can't tell from this agent's data; inferred from last activity."
        }
    }

    private static func healthLine(_ agent: AgentKind, _ health: SourceHealth?, _ now: Date) -> String {
        switch health {
        case .ready:
            return "Reading normally"
        case .failing(_, lastSuccess: let lastSuccess):
            let when = lastSuccess.map { "last read \(formatDuration(now.timeIntervalSince($0))) ago" }
                ?? "never read"
            return "Couldn't read this agent's data (\(when)). This session may be out of date."
        case .absent, nil:
            return "No data source on disk"
        }
    }
}
