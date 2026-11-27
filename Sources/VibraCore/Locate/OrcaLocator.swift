import Foundation

/// Finds the Orca terminal or chat a process runs in.
///
/// Orca sets `ORCA_TERMINAL_HANDLE` in every terminal it starts and
/// `ORCA_AGENT_SESSION_ID` in every chat, so the link is published per process
/// and needs no matching on a directory or title.
public enum OrcaLocator {
    public static let bundleID = "com.stablyai.orca"

    public static func terminalHandle(of pid: Int32) -> String? {
        ProcessInspector.environmentValue("ORCA_TERMINAL_HANDLE", of: pid).flatMap(validHandle)
    }

    /// Held to the shape Orca issues, so nothing else from a process's
    /// environment can reach the command line.
    static func validHandle(_ value: String) -> String? {
        value.range(of: #"^term_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) == nil ? nil : value
    }

    public static func agentSessionID(of pid: Int32) -> String? {
        ProcessInspector.environmentValue("ORCA_AGENT_SESSION_ID", of: pid).flatMap(validAgentSessionID)
    }

    static func validAgentSessionID(_ value: String) -> String? {
        value.range(of: #"^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$"#, options: .regularExpression) == nil ? nil : value
    }

    /// The one worktree `orca agent show --json` places the agent in. Nil for a
    /// closed chat, one open in several worktrees, and a folder workspace,
    /// which Orca's CLI cannot activate.
    public static func worktreeID(inAgentShow reply: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let places = result["places"] as? [[String: Any]]
        else { return nil }
        let worktrees = Set(places.compactMap { $0["worktreeId"] as? String })
        guard worktrees.count == 1, let id = worktrees.first, !id.hasPrefix("folder:") else { return nil }
        return id
    }
}
