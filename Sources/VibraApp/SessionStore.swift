import Foundation
import VibraCore

/// Polls every registered adapter and publishes the merged session list.
///
/// Adapters are injected rather than constructed here so the store can be
/// exercised with fakes, and so adding a fourth agent never means editing this
/// file.
@MainActor
final class SessionStore {
    private(set) var sessions: [Session] = []
    private let adapters: [any AgentAdapter]
    private let engine: StateEngine
    /// Sessions untouched for longer than this are not shown at all.
    ///
    /// Without this the list is every session ever recorded - 491 on the
    /// development machine - which is an archive, not a status display.
    private let activityWindow: TimeInterval
    private var timer: Timer?

    /// Called whenever the session list changes, with the previous list so
    /// callers can detect transitions (e.g. into `awaitingInput`).
    var onChange: (([Session], [Session]) -> Void)?

    init(
        adapters: [any AgentAdapter],
        engine: StateEngine = StateEngine(),
        activityWindow: TimeInterval = 12 * 3600
    ) {
        self.adapters = adapters
        self.engine = engine
        self.activityWindow = activityWindow
    }

    func start(interval: TimeInterval = 2.0) {
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        // discoverSessionsSafely: a broken or absent agent must degrade to
        // "no sessions", never take the menu bar down with it.
        let now = Date()
        let fresh = adapters
            .flatMap { $0.discoverSessionsSafely() }
            .filter { now.timeIntervalSince($0.lastActivity) <= activityWindow }
            .map { session -> Session in
                // Adapters report WHAT happened; StateEngine decides what that
                // means. Keeping the rules in one place is why all three
                // agents classify identically.
                var s = session
                s.state = engine.classify(
                    lastEvent: session.lastEvent,
                    lastActivity: session.lastActivity,
                    now: now
                )
                return s
            }
            .sorted { $0.lastActivity > $1.lastActivity }

        guard fresh != sessions else { return }
        let previous = sessions
        sessions = fresh
        onChange?(previous, fresh)
    }

    var attentionCount: Int { sessions.filter { $0.state.needsAttention }.count }
    var workingCount: Int { sessions.filter { $0.state == .working }.count }
}
