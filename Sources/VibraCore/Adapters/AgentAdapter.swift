import Foundation

/// Reads sessions for exactly one `AgentKind` from that agent's on-disk state.
///
/// Adapters are read-only by contract. An adapter that writes to, locks, or
/// otherwise mutates the observed agent's files is a bug: Vibra is a passive
/// observer and must never be able to damage the tool it is watching.
public protocol AgentAdapter: Sendable {
    var kind: AgentKind { get }

    /// Whether this agent appears to be installed and has state to read.
    /// Must not throw - a missing agent is normal, not an error.
    var isAvailable: Bool { get }

    /// Current sessions, newest activity first. Implementations should tolerate
    /// partially-written records rather than throwing, since the observed agent
    /// may be mid-append.
    ///
    /// This is the full-parse path. It is correct but expensive, and is kept
    /// for tests and for the initial load; steady-state polling goes through
    /// `sources()` + `update(...)` instead.
    func discoverSessions() throws -> [Session]

    /// Cheap enumeration of readable units — one per transcript file, or a
    /// single entry for a database. Must only stat, never read contents.
    ///
    /// Returning an empty array opts the adapter out of incremental ingest,
    /// and `SessionIngest` falls back to `discoverSessions()`.
    func sources() throws -> [SourceDescriptor]

    /// Timestamped usage slices for reporting, extracted from raw records.
    ///
    /// Separate from `update` on purpose. `Session` is the poll-path hot row —
    /// compared and encoded on every refresh — so a growing per-day map on it
    /// would threaten the idle-cost property Phase 0 recovered. Reports
    /// re-read their own window and accumulate these instead.
    ///
    /// Returning an empty array means the adapter cannot attribute usage in
    /// time, and its totals are reported as undated rather than guessed at.
    func usageSamples(from records: [String]) -> [UsageSample]

    /// Folds one source's new input into its previous state.
    func update(
        source: SourceDescriptor,
        input: SourceInput,
        previous: ParsedState?
    ) throws -> ParsedState
}

public extension AgentAdapter {
    /// Default: no incremental support. The adapter is still correct, just
    /// not cheap, and `SessionIngest` will full-parse it every refresh.
    func sources() throws -> [SourceDescriptor] { [] }

    /// Default: no per-record attribution available.
    func usageSamples(from records: [String]) -> [UsageSample] { [] }

    /// Default: ignore the incremental input and full-parse.
    func update(
        source: SourceDescriptor,
        input: SourceInput,
        previous: ParsedState?
    ) throws -> ParsedState {
        ParsedState(sessions: try discoverSessions(), checkpoint: nil)
    }

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
    /// Root under which all agent state is looked up.
    ///
    /// `VIBRA_HOME` overrides it. A bundled app resolves `NSHomeDirectory()`
    /// from the password database rather than `$HOME`, so without an explicit
    /// override there is no way to point Vibra at a fixture tree — which makes
    /// it impossible to test behaviour against malformed or absent agent data
    /// without touching the developer's real sessions.
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["VIBRA_HOME"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
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
    public static var cursorStateDB: URL {
        home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }
    /// VS Code's `User` directories: the stable release, then Insiders.
    public static var vsCodeUserDirectories: [URL] {
        ["Code", "Code - Insiders"].map {
            home.appendingPathComponent("Library/Application Support/\($0)/User")
        }
    }
}
