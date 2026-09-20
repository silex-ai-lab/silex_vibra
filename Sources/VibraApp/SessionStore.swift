import Foundation
import VibraCore

/// Publishes the merged, classified session list to the UI.
///
/// Refreshes are *event driven*, not polled. The previous design ran a timer
/// every 2s and did a full 13.4s re-parse inside it, so work queued faster
/// than it drained and the app sat at ~97% CPU. Now `FileWatcher` says what
/// changed, `SessionIngest` reads only that, and overlapping requests are
/// coalesced rather than stacked.
@MainActor
final class SessionStore {
    private(set) var sessions: [Session] = []

    private let ingest: SessionIngest
    private let engine: StateEngine
    /// Sessions untouched for longer than this are not shown at all. Without
    /// it the list is every session ever recorded — 491 on the development
    /// machine — which is an archive, not a status display.
    private let activityWindow: TimeInterval

    private var watcher: FileWatcher?
    private var safetyTimer: Timer?

    /// Coalescing guards. `refreshRequested` means "something changed while a
    /// refresh was already running"; we loop once more rather than enqueueing
    /// another full pass per event.
    private var isRefreshing = false
    private var refreshRequested = false

    /// Called whenever the session list changes, with the previous list so
    /// callers can detect transitions (e.g. into `awaitingInput`).
    var onChange: (([Session], [Session]) -> Void)?

    init(
        adapters: [any AgentAdapter],
        engine: StateEngine = StateEngine(),
        activityWindow: TimeInterval = 12 * 3600
    ) {
        self.ingest = SessionIngest(adapters: adapters)
        self.engine = engine
        self.activityWindow = activityWindow
    }

    /// `safetyInterval` is a backstop, not the primary mechanism: FSEvents
    /// coalesces and can drop events, and Apple documents a rescan as the
    /// required response. It re-stats; it does not re-parse unchanged files.
    func start(safetyInterval: TimeInterval = 60) {
        Task { await self.requestRefresh() }

        watcher = FileWatcher(
            watchedDirectories: [VibraPaths.claudeProjects, VibraPaths.codexSessions],
            pollURL: VibraPaths.openCodeDB
        ) { [weak self] _ in
            Task { @MainActor in await self?.requestRefresh() }
        }
        watcher?.start()

        let t = Timer.scheduledTimer(withTimeInterval: safetyInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.requestRefresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        safetyTimer = t
    }

    func stop() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        watcher?.stop()
        watcher = nil
    }

    /// Coalesces concurrent requests into at most one extra pass.
    func requestRefresh() async {
        guard !isRefreshing else {
            refreshRequested = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshRequested = false
            await performRefresh()
        } while refreshRequested
    }

    private func performRefresh() async {
        // The read happens on the ingest actor; only the finished snapshot
        // crosses back to the main actor.
        let raw = await ingest.refresh()
        let now = Date()

        let fresh = raw
            .filter { now.timeIntervalSince($0.lastActivity) <= activityWindow }
            .map { session -> Session in
                // Adapters report WHAT happened; StateEngine decides what that
                // means, so all three classify identically.
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

    /// Bytes read from disk during the most recent refresh. Zero on a refresh
    /// where nothing changed — that is the property Phase 0 exists to deliver.
    func lastRefreshBytesRead() async -> Int {
        await ingest.lastRefreshBytesRead
    }

    var attentionCount: Int { sessions.filter { $0.state.needsAttention }.count }
    var workingCount: Int { sessions.filter { $0.state == .working }.count }
}
