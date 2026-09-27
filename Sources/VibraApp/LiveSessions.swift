import Foundation
import VibraCore

/// The impure half of the live-session pipeline: gathers what the process
/// table, the Claude app and the running editors know, then hands everything
/// to `LivePipeline`. The menu (`SessionStore`) and `--query` both come
/// through here, so they cannot disagree.
enum LiveSessions {
    static func snapshot(
        raw: [Session],
        settings: VibraSettings,
        activityWindow: TimeInterval? = nil,
        desktopIndex: ClaudeDesktopIndex = ClaudeDesktopIndex(),
        now: Date = Date()
    ) async -> [Session] {
        let recent = LivePipeline.recent(raw, settings: settings, activityWindow: activityWindow, now: now)

        // A session whose process has exited is over. Off the main actor,
        // since Codex's check runs lsof.
        let candidates = Dictionary(grouping: recent, by: \.agent).mapValues { $0.map(\.id) }
        let (live, claudeStatus, desktop) = await Task.detached {
            let locator = ProcessLocator()
            let claudeStatus = locator.claudeLiveStatuses()
            var live: [AgentKind: Set<String>] = [:]
            for (agent, ids) in candidates {
                live[agent] = agent == .claudeCode
                    ? Set(claudeStatus.keys)
                    : locator.liveSessionIDs(agent: agent, candidates: ids)
            }
            return (live, claudeStatus, desktopIndex.load())
        }.value

        return LivePipeline.finish(
            recent,
            desktop: desktop,
            claudeStatus: claudeStatus,
            live: live,
            editorLaunch: TerminalJumper.editorLaunchTimes()
        )
    }
}
