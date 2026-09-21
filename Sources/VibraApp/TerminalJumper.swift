import AppKit
import Foundation
import VibraCore

/// Focuses the terminal tab a session is running in.
///
/// The chain is exact at every link: session id → pid (published by the agent
/// itself) → controlling tty (`ps`) → terminal tab (the emulator's own tty
/// report). Nothing is matched on working directory, because a directory does
/// not identify a session — two agents routinely share one.
///
/// A tty that no terminal claims is **not** jumpable, and that is reported
/// rather than guessed at. The common cause is a multiplexer: tmux, screen or
/// herdr own their panes' ptys, so the emulator never sees them.
enum TerminalJumper {

    enum Outcome: Equatable {
        case jumped(app: String)
        /// The session has no locatable process: it exited, or its agent
        /// publishes no pid link.
        case notLocatable
        /// The process exists but has no controlling terminal.
        case noControllingTerminal
        /// No terminal claims this tty — usually a multiplexer pane.
        case noTerminalOwnsTTY(String)
    }

    static func jump(to session: Session, locator: ProcessLocator = ProcessLocator()) -> Outcome {
        guard let found = locator.locate(sessionID: session.id, agent: session.agent) else {
            return .notLocatable
        }
        guard let tty = found.tty else { return .noControllingTerminal }

        if focusITerm(tty: tty) { return .jumped(app: "iTerm2") }
        if focusTerminalApp(tty: tty) { return .jumped(app: "Terminal") }
        return .noTerminalOwnsTTY(tty)
    }

    // MARK: - Emulators

    private static func focusITerm(tty: String) -> Bool {
        guard isRunning(bundleID: "com.googlecode.iterm2") else { return false }
        return runAppleScript("""
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if my normalize(tty of s) is "\(tty)" then
                  select w
                  select t
                  select s
                  activate
                  return "ok"
                end if
              end repeat
            end repeat
          end repeat
        end tell
        return "no"
        on normalize(v)
          if v starts with "/dev/" then return text 6 thru -1 of v
          return v
        end normalize
        """)
    }

    private static func focusTerminalApp(tty: String) -> Bool {
        guard isRunning(bundleID: "com.apple.Terminal") else { return false }
        return runAppleScript("""
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if my normalize(tty of t) is "\(tty)" then
                set selected tab of w to t
                set index of w to 1
                activate
                return "ok"
              end if
            end repeat
          end repeat
        end tell
        return "no"
        on normalize(v)
          if v starts with "/dev/" then return text 6 thru -1 of v
          return v
        end normalize
        """)
    }

    /// Only script an emulator that is already running: asking for one that
    /// is not would launch it, which is never what a jump means.
    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        if error != nil { return false }
        return result.stringValue == "ok"
    }
}
