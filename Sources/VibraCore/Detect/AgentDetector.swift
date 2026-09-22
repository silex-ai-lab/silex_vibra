import Foundation

/// What Vibra found for one agent.
public struct AgentDetection: Sendable, Equatable {
    public let kind: AgentKind
    /// The agent has readable state on disk.
    public let isPresent: Bool
    /// Number of readable sources (transcripts, or 1 for a database).
    public let sourceCount: Int
    /// Most recent write across those sources, if any.
    public let lastActivity: Date?

    public init(kind: AgentKind, isPresent: Bool, sourceCount: Int, lastActivity: Date?) {
        self.kind = kind
        self.isPresent = isPresent
        self.sourceCount = sourceCount
        self.lastActivity = lastActivity
    }

    /// Present, and written to within the window — i.e. worth showing.
    public func isActive(within window: TimeInterval, now: Date = Date()) -> Bool {
        guard isPresent, let lastActivity else { return false }
        return now.timeIntervalSince(lastActivity) <= window
    }
}

/// Decides which agents to monitor by looking at what is actually on disk.
///
/// **State on disk, not a binary on `PATH`.** The two answer different
/// questions. An installed CLI that has never run has nothing to show and
/// would appear as a permanently empty row; a CLI that has been uninstalled
/// may still have transcripts worth reading. What matters is whether there is
/// something to read.
///
/// Detection is also deliberately cheap — it stats, it never parses — so it
/// can run at launch without reintroducing the cost Phase 0 removed.
public struct AgentDetector: Sendable {
    private let adapters: [any AgentAdapter]

    public init(adapters: [any AgentAdapter]) {
        self.adapters = adapters
    }

    public func detectAll() -> [AgentDetection] {
        AgentKind.allCases.compactMap { kind in
            guard let adapter = adapters.first(where: { $0.kind == kind }) else { return nil }
            return detect(adapter)
        }
    }

    public func detect(_ adapter: any AgentAdapter) -> AgentDetection {
        guard adapter.isAvailable else {
            return AgentDetection(kind: adapter.kind, isPresent: false, sourceCount: 0, lastActivity: nil)
        }
        let sources = (try? adapter.sources()) ?? []
        return AgentDetection(
            kind: adapter.kind,
            isPresent: true,
            sourceCount: sources.count,
            lastActivity: sources.map(\.modified).max()
        )
    }

    /// Adapters worth polling: those with state on disk.
    ///
    /// Absent agents are dropped rather than polled and skipped, so supporting
    /// an agent nobody has installed costs nothing at runtime.
    public func activeAdapters() -> [any AgentAdapter] {
        adapters.filter { $0.isAvailable }
    }
}
