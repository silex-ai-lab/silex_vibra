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
    private let settingsStore: any SettingsStore

    /// Fixed values that win over the per-refresh settings load. Only the
    /// diagnostics set these (`--dump-sessions --all` shows everything,
    /// whatever the user's activity window is).
    struct Overrides {
        /// Sessions quiet for longer than this are not shown.
        var activityWindow: TimeInterval
        /// Sources untouched for longer than this are never read; nil reads all.
        var horizon: TimeInterval?
    }
    private let overrides: Overrides?

    /// The settings the last refresh used.
    private(set) var settings: VibraSettings

    private var watcher: FileWatcher?
    private let desktopIndex = ClaudeDesktopIndex()
    private var safetyTimer: Timer?

    /// Coalescing guards. `refreshRequested` means "something changed while a
    /// refresh was already running"; we loop once more rather than enqueueing
    /// another full pass per event.
    private var isRefreshing = false
    private var refreshRequested = false

    /// Called whenever the session list changes, with the previous list so
    /// callers can detect transitions (e.g. into `awaitingInput`).
    var onChange: (([Session], [Session]) -> Void)?

    /// Sessions untouched for longer than the activity window (a setting,
    /// 12 h by default) are not shown at all. Without it the list is every
    /// session ever recorded — 491 on the development machine — which is an
    /// archive, not a status display.
    init(
        adapters: [any AgentAdapter],
        settingsStore: any SettingsStore = PreferencesStore(),
        overrides: Overrides? = nil
    ) {
        self.settingsStore = settingsStore
        self.overrides = overrides
        let settings = VibraSettings.load(from: settingsStore)
        self.settings = settings
        self.ingest = SessionIngest(
            adapters: adapters,
            horizon: overrides.map(\.horizon) ?? settings.activityWindowSeconds
        )
    }

    /// `safetyInterval` is a backstop, not the primary mechanism: FSEvents
    /// coalesces and can drop events, and Apple documents a rescan as the
    /// required response. It re-stats; it does not re-parse unchanged files.
    func start(safetyInterval: TimeInterval = 60) {
        Task { await self.requestRefresh() }

        // VS Code writes one chat log per session under these.
        let vsCodeChatDirectories = VibraPaths.vsCodeUserDirectories.flatMap { user in
            [
                user.appendingPathComponent("workspaceStorage"),
                user.appendingPathComponent("globalStorage/emptyWindowChatSessions"),
            ]
        }
        watcher = FileWatcher(
            // ~/.claude/sessions too: an exiting session only deletes its
            // <pid>.json there, and without this it lingered in the menu until
            // the safety rescan.
            watchedDirectories: [
                VibraPaths.claudeProjects,
                VibraPaths.codexSessions,
                VibraPaths.home.appendingPathComponent(".claude/sessions"),
                // Cursor writes its agent state into this directory's database.
                VibraPaths.cursorStateDB.deletingLastPathComponent(),
                // Archiving or renaming in the Claude UI only touches this.
                VibraPaths.home.appendingPathComponent(
                    "Library/Application Support/Claude/claude-code-sessions"),
            ] + vsCodeChatDirectories,
            pollURLs: [VibraPaths.openCodeDB, VibraPaths.hermesStateDB]
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
        // Settings are re-read every refresh, so a change in the Settings
        // window (or a `defaults write`) applies without a relaunch.
        settings = VibraSettings.load(from: settingsStore)
        if overrides == nil {
            await ingest.setHorizon(settings.activityWindowSeconds)
        }

        // The read happens on the ingest actor; only the finished snapshot
        // crosses back to the main actor.
        let raw = await ingest.refresh()
        let fresh = await LiveSessions.snapshot(
            raw: raw,
            settings: settings,
            activityWindow: overrides?.activityWindow,
            desktopIndex: desktopIndex
        )

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
