import Foundation
import VibraCore

/// The single place that knows which concrete adapters exist.
///
/// Adding an agent is a one-line change here rather than surgery on app
/// startup. Which of them have anything to show is decided each refresh from
/// what is on disk, not from this list.
enum AdapterRegistry {
    /// Every adapter Vibra can speak. All of them are handed to ingest, which
    /// skips an adapter whose state is not on disk with a single stat, so an
    /// agent first used after Vibra starts is picked up without a relaunch.
    static func all() -> [any AgentAdapter] {
        [
            ClaudeCodeAdapter(),
            CodexAdapter(),
            OpenCodeAdapter(),
            CursorAdapter(),
            VSCodeAdapter(),
            HermesAdapter(),
        ]
    }

    static func detections() -> [AgentDetection] {
        AgentDetector(adapters: all()).detectAll()
    }
}
