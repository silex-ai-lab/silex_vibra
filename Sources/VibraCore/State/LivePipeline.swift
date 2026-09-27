import Foundation

/// The pure half of turning raw adapter output into what the menu shows.
///
/// Everything here is a function of its inputs, so the composition the menu,
/// `--query` and `--dump-sessions` share is unit-tested in one place. The
/// inputs that need I/O (process table, desktop index, editor launch times)
/// are gathered by the app and passed in.
public enum LivePipeline {
    /// Drops sessions quiet for longer than the activity window, classifies
    /// the rest with the given settings, newest first. This is the pipeline's
    /// only sort.
    ///
    /// `activityWindow` overrides the settings' window when given, for the
    /// diagnostics that must see everything (`--dump-sessions --all`).
    public static func recent(
        _ raw: [Session],
        settings: VibraSettings,
        activityWindow: TimeInterval? = nil,
        now: Date
    ) -> [Session] {
        let window = activityWindow ?? settings.activityWindowSeconds
        let engine = StateEngine(config: settings.stateEngineConfig)
        return raw
            .filter { now.timeIntervalSince($0.lastActivity) <= window }
            .map { session -> Session in
                // Adapters report WHAT happened; StateEngine decides what that
                // means, so every adapter classifies identically.
                var s = session
                s.state = engine.classify(
                    lastEvent: session.lastEvent,
                    lastActivity: session.lastActivity,
                    now: now
                )
                return s
            }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Applies what the Claude app and live processes know: titles and
    /// archiving, then exited sessions dropped, then orphaned editor sessions
    /// settled. Order is preserved from `recent`.
    public static func finish(
        _ recent: [Session],
        desktop: [String: DesktopSessionInfo],
        claudeStatus: [String: ClaudeLiveStatus],
        live: [AgentKind: Set<String>],
        editorLaunch: [String: Date]
    ) -> [Session] {
        let enriched = Session.enriched(recent, desktop: desktop, live: claudeStatus)
        return Session.settlingOrphaned(
            Session.withoutExited(enriched, live: live),
            editorLaunch: editorLaunch
        )
    }
}
