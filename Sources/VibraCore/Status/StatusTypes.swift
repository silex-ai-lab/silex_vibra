import Foundation

/// A session's identity across agents. Two agents can use the same session id.
public struct SessionKey: Hashable, Sendable {
    public let agent: AgentKind
    public let id: String

    public init(agent: AgentKind, id: String) {
        self.agent = agent
        self.id = id
    }
}

/// Why a source could not be read. Deliberately an enum: it cannot carry error text, a path or a record.
public enum SourceProblem: String, Sendable, CaseIterable {
    case listFailed, readFailed, parseFailed
}

public enum SourceHealth: Sendable, Equatable {
    /// `isAvailable` is false: no state on disk. Says nothing about whether the agent is installed.
    case absent
    case ready(lastSuccess: Date?)
    case failing(SourceProblem, lastSuccess: Date?)
}

/// When a session started waiting on the user, and how Vibra knows.
public enum AttentionStart: Sendable, Equatable {
    /// Vibra saw the state change.
    case observed(Date)
    /// Already in this state when first seen; the true start is unknown.
    case firstSeen(Date)

    public var date: Date {
        switch self {
        case .observed(let date), .firstSeen(let date): date
        }
    }
}

public struct StatusSnapshot: Sendable, Equatable {
    public var sessions: [Session]
    public var health: [AgentKind: SourceHealth]
    public var attention: [SessionKey: AttentionStart]

    public init(
        sessions: [Session] = [],
        health: [AgentKind: SourceHealth] = [:],
        attention: [SessionKey: AttentionStart] = [:]
    ) {
        self.sessions = sessions
        self.health = health
        self.attention = attention
    }
}
