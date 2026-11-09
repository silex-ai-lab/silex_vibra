import Foundation

/// Finds the Orca terminal a process runs in.
///
/// Orca sets `ORCA_TERMINAL_HANDLE` in every terminal it starts, so the link is
/// published per process and needs no matching on a directory or title.
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
}
