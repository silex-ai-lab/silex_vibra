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
        /// macOS refused the Apple Event. Vibra has not been granted permission
        /// to control this terminal, which is a settings problem, not a tty one.
        case notPermitted(app: String)
    }

    /// Why a session cannot be jumped to at all, found without focusing
    /// anything: `.notLocatable` or `.noControllingTerminal`, or nil when a jump
    /// might work. Checks exactly what `jump` checks first, so a session this
    /// calls a dead end is one `jump` would fail on for the same reason.
    static func deadEnd(for session: Session, locator: ProcessLocator = ProcessLocator()) -> Outcome? {
        if session.desktopSessionID != nil || session.agent == .cursor || session.agent == .vsCode {
            return nil
        }
        guard let found = locator.locate(sessionID: session.id, agent: session.agent) else {
            return .notLocatable
        }
        if found.desktopSessionID != nil { return nil }
        if found.tty == nil, hostApp(of: found.pid) == nil { return .noControllingTerminal }
        return nil
    }

    static func jump(to session: Session, locator: ProcessLocator = ProcessLocator()) -> Outcome {
        // Cursor's agents live inside the Cursor window. It publishes no link
        // Vibra can open a specific chat with, so the app is brought forward
        // with the chat's own sidebar entry there to click.
        if session.agent == .cursor {
            return session.editorBundleID.flatMap(activateApp(bundleID:)).map { .jumped(app: $0) } ?? .notLocatable
        }
        // Copilot chats live in a VS Code window. VS Code has no link to one
        // chat either, but opening the chat's folder in it focuses the window
        // that folder is open in, which is where the chat is.
        if session.agent == .vsCode {
            return focusVSCode(session).map { .jumped(app: $0) } ?? .notLocatable
        }
        // A Claude UI session opens in the app by its desktop id, whether or
        // not the desktop app currently has a process running for it.
        if let desktopID = session.desktopSessionID, openInClaudeApp(desktopID) {
            return .jumped(app: "Claude")
        }
        guard let found = locator.locate(sessionID: session.id, agent: session.agent) else {
            return .notLocatable
        }
        // Started by the Claude desktop app (a scheduled task or a Code tab):
        // there is no terminal to find, but the app can open the session
        // itself. Before the tty check, which such a session always fails.
        if let desktopID = found.desktopSessionID, openInClaudeApp(desktopID) {
            return .jumped(app: "Claude")
        }
        // No terminal: the agent runs inside an app - the Codex app, or an
        // IDE extension (Codex or Claude Code in VS Code or Cursor). Bring
        // that app forward rather than report a dead end.
        guard let tty = found.tty else {
            if let app = hostApp(of: found.pid), app.activate() {
                return .jumped(app: app.localizedName ?? "its app")
            }
            return .noControllingTerminal
        }

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
        let owner = ProcessInspector.ttyOwner(of: found.pid)
        if owner == .multiplexer("herdr"), let app = focusHerdr(pid: found.pid) {
            return .jumped(app: app)
        }
        return .noTerminalOwnsTTY(tty: tty, owner: owner)
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

    // MARK: - Apps

    /// Launch time of each running editor that hosts agent sessions, keyed by
    /// bundle id. Feeds `Session.settlingOrphaned`.
    static func editorLaunchTimes() -> [String: Date] {
        var launched: [String: Date] = [:]
        for id in ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92"] {
            let dates = NSRunningApplication.runningApplications(withBundleIdentifier: id).compactMap(\.launchDate)
            if let earliest = dates.min() { launched[id] = earliest }
        }
        return launched
    }

    /// Focuses the VS Code window showing the session's folder, or just brings
    /// VS Code forward for a chat in an empty window. Like `activateApp`, never
    /// launches VS Code: with it closed, the chat is not on screen anywhere.
    private static func focusVSCode(_ session: Session) -> String? {
        guard let bundleID = session.editorBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        // Activate first: it is synchronous and reports whether it worked.
        // Opening the folder is asynchronous and reports nothing in time, so
        // on its own it claimed a jump that had not happened.
        guard app.activate() else { return nil }
        var isDir: ObjCBool = false
        if !session.cwd.isEmpty, let appURL = app.bundleURL,
           FileManager.default.fileExists(atPath: session.cwd, isDirectory: &isDir), isDir.boolValue {
            // Picks the window: VS Code focuses the one with this folder open.
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: session.cwd)],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
        return "VS Code"
    }

    /// Brings a running app forward. Never launches one: if it is not running,
    /// the session it would show cannot be live either.
    private static func activateApp(bundleID: String) -> String? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              app.activate()
        else { return nil }
        return app.localizedName ?? bundleID
    }

    /// The nearest ancestor of `pid` that is a regular GUI app - one with a
    /// Dock presence, which is what the user thinks of as "the app". Helpers
    /// and background agents along the way are skipped, so an extension host
    /// resolves to the editor and not to its helper process.
    static func hostApp(of pid: Int32) -> NSRunningApplication? {
        let table = ProcessInspector.processTable()
        var current = pid
        for _ in 0..<32 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy == .regular,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                return app
            }
            guard let parent = table[current]?.ppid, parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    // MARK: - herdr

    /// Focuses the herdr pane running `pid`, then the terminal window showing
    /// that herdr session. Returns the emulator's name, or nil when either half
    /// could not be done - focusing a pane in a herdr nobody is looking at is
    /// not a jump.
    ///
    /// The pane is found exactly: herdr reports each pane's `shell_pid`, and the
    /// session's ancestor directly below the herdr server is that shell. The
    /// window is the one whose tab holds a herdr client for the same session.
    static func focusHerdr(pid: Int32) -> String? {
        let table = ProcessInspector.processTable()
        guard let route = HerdrLocator.route(from: pid, in: table),
              let herdr = herdrExecutable(route)
        else { return nil }
        let session = route.session.map { ["--session", $0] } ?? []

        guard let listing = runHerdr(herdr, session + ["pane", "list"]) else { return nil }
        var match: (paneID: String, tabID: String)?
        for pane in HerdrLocator.parsePaneList(listing) {
            guard let info = runHerdr(herdr, session + ["pane", "process-info", "--pane", pane.paneID])
            else { continue }
            if HerdrLocator.parseShellPID(info) == route.paneShellPID {
                match = pane
                break
            }
        }
        guard let pane = match else { return nil }

        // `agent focus` lands on the pane itself, splits included, and marks
        // it seen; it only accepts panes herdr recognises an agent in, so fall
        // back to the pane's tab. Both switch workspace as needed.
        if runHerdr(herdr, session + ["agent", "focus", pane.paneID]) == nil {
            guard runHerdr(herdr, session + ["tab", "focus", pane.tabID]) != nil else { return nil }
        }

        for clientTTY in HerdrLocator.clientTTYs(of: route.session, in: table) {
            if focusITerm(tty: clientTTY) == .focused { return "herdr in iTerm2" }
            if focusTerminalApp(tty: clientTTY) == .focused { return "herdr in Terminal" }
        }
        return nil
    }

    /// The server's own binary when its command line names it, else the usual
    /// install locations. A GUI app's PATH does not include ~/.local/bin, so
    /// "herdr" alone would not resolve.
    private static func herdrExecutable(_ route: HerdrRoute) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [route.executable].compactMap { $0 } + [
            "\(home)/.local/bin/herdr",
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
            "\(home)/.cargo/bin/herdr",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs one herdr CLI request and returns stdout, or nil on a non-zero
    /// exit (herdr reports errors as JSON on stderr with status 1). Bounded:
    /// a wedged server must not hang the click.
    private static func runHerdr(_ executable: String, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus == 0 ? data : nil
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
