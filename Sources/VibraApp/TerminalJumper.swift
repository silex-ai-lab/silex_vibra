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
/// herdr own their panes' ptys, so the emulator never sees them — but that is
/// now established from the process ancestry instead of assumed. It was
/// assumed, and on a plain iTerm2 tab the assumption was simply wrong.
///
/// The other way a jump fails is macOS refusing the Apple Event. That is a
/// different problem with a different remedy, and it used to be reported as the
/// multiplexer case because every AppleScript error collapsed into one boolean.
enum TerminalJumper {

    enum Outcome: Equatable {
        case jumped(app: String)
        /// The session has no locatable process: it exited, or its agent
        /// publishes no pid link.
        case notLocatable
        /// The process exists but has no controlling terminal.
        case noControllingTerminal
        /// No terminal claims this tty. `owner` says what the process ancestry
        /// actually shows, so the explanation can be true rather than likely.
        case noTerminalOwnsTTY(tty: String, owner: ProcessInspector.TTYOwner)
        /// macOS refused the Apple Event. vibra has not been granted permission
        /// to control this terminal, which is a settings problem, not a tty one.
        case notPermitted(app: String)
    }

    static func jump(to session: Session, locator: ProcessLocator = ProcessLocator()) -> Outcome {
        guard let found = locator.locate(sessionID: session.id, agent: session.agent) else {
            return .notLocatable
        }
        // Started by the Claude desktop app (a scheduled task or a Code tab):
        // there is no terminal to find, but the app can open the session
        // itself. Before the tty check, which such a session always fails.
        if let desktopID = found.desktopSessionID, openInClaudeApp(desktopID) {
            return .jumped(app: "Claude")
        }
        guard let tty = found.tty else { return .noControllingTerminal }

        switch focusITerm(tty: tty) {
        case .focused: return .jumped(app: "iTerm2")
        case .refused: return .notPermitted(app: "iTerm2")
        case .notFound, .notRunning: break
        }
        switch focusTerminalApp(tty: tty) {
        case .focused: return .jumped(app: "Terminal")
        case .refused: return .notPermitted(app: "Terminal")
        case .notFound, .notRunning: break
        }
        return .noTerminalOwnsTTY(tty: tty, owner: ProcessInspector.ttyOwner(of: found.pid))
    }

    /// Why an emulator did not end up focused.
    ///
    /// `refused` is the one that matters: it is macOS denying the Apple Event
    /// (`errAEEventNotPermitted`), not the tab being absent. Folding it into
    /// "not found" is what made a permissions problem look like a tmux problem.
    private enum FocusResult {
        case focused
        case notFound
        case refused
        case notRunning
    }

    // MARK: - Claude desktop app

    /// Opens the session through the desktop app's own deep link, the one it
    /// registers for "Continue Last Claude Code Session". Needs no Automation
    /// permission: it is a URL open, not an Apple Event.
    private static func openInClaudeApp(_ desktopSessionID: String) -> Bool {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: desktopSessionID)]
        guard let url = components.url,
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        else { return false }
        return NSWorkspace.shared.open(url)
    }

    // MARK: - Emulators

    private static func focusITerm(tty: String) -> FocusResult {
        guard isRunning(bundleID: "com.googlecode.iterm2") else { return .notRunning }
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

    private static func focusTerminalApp(tty: String) -> FocusResult {
        guard isRunning(bundleID: "com.apple.Terminal") else { return .notRunning }
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

    /// Runs the script and distinguishes "it said no" from "it was not allowed
    /// to ask".
    ///
    /// `errAEEventNotPermitted` (-1743) is what macOS returns when the app has
    /// no Automation permission for the target. An ad-hoc signed bundle without
    /// `NSAppleEventsUsageDescription` in its Info.plist is never even prompted,
    /// so this was the permanent state of every GUI-launched jump: denied, and
    /// then reported as a missing tty.
    ///
    /// -600 (`procNotFound`) and -1728 (`errAENoSuchObject`) are ordinary
    /// misses, not permission problems.
    private static func runAppleScript(_ source: String) -> FocusResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .notFound }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            return code == -1743 ? .refused : .notFound
        }
        return result.stringValue == "ok" ? .focused : .notFound
    }
}
