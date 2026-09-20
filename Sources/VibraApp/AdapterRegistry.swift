import Foundation
import VibraCore

/// The single place that knows which concrete adapters exist.
///
/// Kept separate from AppDelegate so adding an agent is a one-line change here
/// rather than surgery on app startup.
enum AdapterRegistry {
    static func all() -> [any AgentAdapter] {
        [
            ClaudeCodeAdapter(),
            CodexAdapter(),
            OpenCodeAdapter(),
        ]
    }
}
