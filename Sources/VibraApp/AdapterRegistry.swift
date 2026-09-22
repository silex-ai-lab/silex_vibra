import Foundation
import VibraCore

/// The single place that knows which concrete adapters exist.
///
/// Adding an agent is a one-line change here rather than surgery on app
/// startup. Which of them are actually *used* is decided by `AgentDetector`
/// from what is on disk, not from this list.
enum AdapterRegistry {
    /// Every adapter Vibra can speak, installed or not.
    static func all() -> [any AgentAdapter] {
        [
            ClaudeCodeAdapter(),
            CodexAdapter(),
            OpenCodeAdapter(),
            CursorAdapter(),
        ]
    }

    /// Only the adapters with readable state on this machine.
    ///
    /// An agent nobody has installed costs nothing: it is never polled, and it
    /// never appears as a permanently empty row.
    static func detected() -> [any AgentAdapter] {
        AgentDetector(adapters: all()).activeAdapters()
    }

    static func detections() -> [AgentDetection] {
        AgentDetector(adapters: all()).detectAll()
    }
}
