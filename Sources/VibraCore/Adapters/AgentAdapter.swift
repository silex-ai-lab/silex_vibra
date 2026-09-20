import Foundation

/// Reads sessions for exactly one `AgentKind` from that agent's on-disk state.
///
/// Adapters are read-only by contract. An adapter that writes to, locks, or
/// otherwise mutates the observed agent's files is a bug: vibra is a passive
/// observer and must never be able to damage the tool it is watching.
public protocol AgentAdapter: Sendable {
    var kind: AgentKind { get }

    /// Whether this agent appears to be installed and has state to read.
    /// Must not throw - a missing agent is normal, not an error.
    var isAvailable: Bool { get }

    /// Current sessions, newest activity first. Implementations should tolerate
    /// partially-written records rather than throwing, since the observed agent
    /// may be mid-append.
    func discoverSessions() throws -> [Session]
}

public extension AgentAdapter {
    /// Sessions, or an empty list if the source is unreadable. The menu bar
    /// should degrade to "no sessions" rather than disappear on a parse error.
    func discoverSessionsSafely() -> [Session] {
        guard isAvailable else { return [] }
        return (try? discoverSessions()) ?? []
    }
}

/// Standard locations the adapters read. Overridable so tests can point at
/// fixtures instead of the developer's real, live agent state.
public enum VibraPaths {
    public static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }
    public static var claudeProjects: URL {
        home.appendingPathComponent(".claude/projects")
    }
    public static var codexSessions: URL {
        home.appendingPathComponent(".codex/sessions")
    }
    public static var openCodeDB: URL {
        home.appendingPathComponent(".local/share/opencode/opencode.db")
    }
}
