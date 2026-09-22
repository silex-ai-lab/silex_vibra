import AppKit
import VibraCore

/// Owns the status item and renders the session list into its menu.
///
/// The status item title is deliberately terse: a glanceable count, not a
/// sentence. Detail belongs in the dropdown, where it costs the user a click
/// they chose to spend.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let store: SessionStore
    private let notchOverlay: NotchOverlay?
    private lazy var reportWindow = ReportWindowController(adapters: AdapterRegistry.detected())
    private let notificationSink = UserNotificationSink()
    private lazy var notifier = AttentionNotifier(sink: notificationSink)
    private var hasBaseline = false

    init(store: SessionStore) {
        self.store = store
        // nil on a machine with no notch - the whole feature no-ops rather
        // than drawing a floating panel where no notch exists.
        self.notchOverlay = NotchOverlay.makeIfSupported()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem = item

        // Ask once, up front. Delivery is not guaranteed for an ad-hoc signed
        // bundle, so a refusal here must not be fatal - the menu bar still
        // shows everything the notification would have said.
        notificationSink.requestAuthorizationIfNeeded()
        notificationSink.onClick { [weak self] sessionID, key in
            self?.jumpFromNotification(sessionID: sessionID, key: key)
        }

        store.onChange = { [weak self] previous, sessions in
            guard let self else { return }
            self.render(sessions)
            self.notchOverlay?.update(sessions: sessions)
            // The first snapshot is a baseline, not a transition. Diffed
            // against an empty list, every session that was already waiting -
            // some for hours - looked like it had just started to, and each
            // launch re-alerted for all of them.
            self.notifier.notifyIfNeeded(
                previous: self.hasBaseline ? previous : sessions,
                current: sessions
            )
            self.hasBaseline = true
            self.notificationSink.removeDelivered(except: self.notifier.outstandingKeys)
        }
        render(store.sessions)
        store.start()
    }

    /// Clears vibra's own delivered notifications on the way out.
    ///
    /// A "waiting for you" banner that outlives the process is unactionable —
    /// the menu bar it points at is gone — so leaving it behind is noise the
    /// user has to dismiss by hand.
    func shutdown() {
        notifier.withdrawAll()
    }

    private func render(_ sessions: [Session]) {
        guard let item = statusItem else { return }
        item.button?.title = summaryTitle(sessions)
        item.menu = buildMenu(sessions)
    }

    /// e.g. "vibra 2▶ 1!"  - working count, then attention count.
    private func summaryTitle(_ sessions: [Session]) -> String {
        let working = sessions.filter { $0.state == .working }.count
        let attention = sessions.filter { $0.state.needsAttention }.count
        if sessions.isEmpty { return "vibra" }
        var parts: [String] = []
        if working > 0 { parts.append("\(working)▶") }
        if attention > 0 { parts.append("\(attention)!") }
        return parts.isEmpty ? "vibra" : parts.joined(separator: " ")
    }

    private func buildMenu(_ sessions: [Session]) -> NSMenu {
        let menu = NSMenu()

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            // Attention-needing sessions float to the top: the entire point of
            // the app is surfacing the one that is waiting on you.
            let ordered = sessions.sorted { lhs, rhs in
                if lhs.state.needsAttention != rhs.state.needsAttention {
                    return lhs.state.needsAttention
                }
                return lhs.lastActivity > rhs.lastActivity
            }
            for group in AgentKind.allCases {
                let inGroup = ordered.filter { $0.agent == group }
                guard !inGroup.isEmpty else { continue }
                menu.addItem(sectionHeader(group.displayName))
                for session in inGroup { menu.addItem(row(for: session)) }
                menu.addItem(.separator())
            }
        }

        menu.addItem(.separator())
        let report = NSMenuItem(title: "Usage Report…", action: #selector(showReport), keyEquivalent: "u")
        report.target = self
        menu.addItem(report)
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Quit vibra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    private func row(for session: Session) -> NSMenuItem {
        let tokens = session.usage.total
        let tokenText = tokens >= 1000 ? "\(tokens / 1000)k tok" : "\(tokens) tok"
        let label = "\(dot(session.state)) \(session.projectName) · \(stateText(session.state)) · \(tokenText)"
        let item = NSMenuItem(title: label, action: #selector(jumpToSession(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = session
        item.toolTip = "\(session.cwd)\n\(session.model ?? "unknown model")\n\nClick to focus its terminal tab."
        return item
    }

    /// Clicking a row focuses the terminal the session runs in.
    ///
    /// When that is not possible the reason is shown rather than silently
    /// doing nothing — most often the session lives in a multiplexer pane
    /// (tmux, screen, herdr), whose pty the terminal emulator never sees.
    @objc private func jumpToSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? Session else { return }
        explainFailure(TerminalJumper.jump(to: session), for: session)
    }

    /// A clicked notification jumps like a clicked menu row, and on success the
    /// notification is cleared: it has taken you where it pointed.
    ///
    /// A dead end - no process to find, or a process with no terminal - is not
    /// going to change on a second click, so that notification is cleared too,
    /// and so is every other outstanding one that is a dead end for the same
    /// reason: you found out by clicking one, and should not have to click
    /// through the rest to find out again. Any other failure (a permission, a
    /// multiplexer pane) removes only the clicked notification: a clicked
    /// notification never stays behind.
    ///
    /// A session no longer in the snapshot is not jumped to, and its
    /// notification is removed.
    private func jumpFromNotification(sessionID: String, key: String) {
        // Gone from the snapshot: exited, or aged out. Nothing to jump to, and
        // nothing the notification says is still true.
        guard let session = store.sessions.first(where: { $0.id == sessionID }) else {
            notifier.dismiss(key: key)
            return
        }
        let outcome = TerminalJumper.jump(to: session)
        switch outcome {
        case .jumped:
            notifier.dismiss(key: key)
        case .notLocatable, .noControllingTerminal:
            // By key, not by session: the clicked notification is removed even
            // when it was left behind by an earlier run and never tracked here.
            notifier.dismiss(key: key)
            let others = dismissDeadEndNotifications()
            // Withdrawn before the alert: it is modal, and the sweep should not
            // wait on the user reading it.
            explainFailure(
                outcome, for: session,
                footnote: others > 0
                    ? "\n\nCleared this notification and \(others) other"
                      + (others == 1 ? "" : "s") + " that can't be reached either."
                    : "\n\nCleared this notification."
            )
        case .notPermitted, .noTerminalOwnsTTY:
            // Clicked, so it goes too. Only the sweep is withheld: a
            // permission can be granted, so the others may still work.
            notifier.dismiss(key: key)
            explainFailure(outcome, for: session)
        }
    }

    /// Withdraws every outstanding notification whose session is a dead end.
    /// Returns how many it withdrew.
    private func dismissDeadEndNotifications() -> Int {
        let byID = Dictionary(
            store.sessions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var count = 0
        for id in notifier.outstandingSessionIDs {
            guard let session = byID[id], TerminalJumper.deadEnd(for: session) != nil
            else { continue }
            notifier.dismiss(sessionID: id)
            count += 1
        }
        return count
    }

    /// Tells the user why a jump failed. Does nothing for a jump that worked.
    private func explainFailure(
        _ outcome: TerminalJumper.Outcome,
        for session: Session,
        footnote: String = ""
    ) {
        switch outcome {
        case .jumped:
            return
        case .notLocatable:
            explain(
                "Can't find that session's process",
                "\(session.agent.displayName) doesn't publish a link between its "
                + "session and its process, or the process has exited." + footnote
            )
        case .noControllingTerminal:
            explain(
                "That session has no terminal",
                "Its process is running without a controlling terminal, so there "
                + "is no tab to focus." + footnote
            )
        case .notPermitted(let app):
            explain(
                "vibra isn't allowed to control \(app)",
                "macOS refused the Apple Event. Focusing a tab means asking "
                + "\(app) which one owns the session's terminal, and that needs "
                + "Automation permission.\n\nSystem Settings → Privacy & Security "
                + "→ Automation → Vibra → enable \(app).\n\nIf Vibra isn't listed "
                + "there yet, it has never been able to ask — reinstall with "
                + "`make install` and try once more.\n\nNote: vibra is ad-hoc "
                + "signed, so rebuilding it changes its identity and macOS may "
                + "ask again."
            )
        case .noTerminalOwnsTTY(let tty, let owner):
            switch owner {
            case .multiplexer(let name):
                explain(
                    "\(tty) belongs to \(name)",
                    "\(name) owns its panes' terminals, so the emulator never "
                    + "sees them and can't be asked to focus one.\n\nvibra will "
                    + "not guess at a different tab."
                )
            case .emulator(let name):
                explain(
                    "\(name) has that session, but didn't focus it",
                    "\(tty) traces back to \(name), so this is not a multiplexer "
                    + "pane — \(name) just didn't report a tab owning that tty. "
                    + "A detached or restored session can do this.\n\nvibra will "
                    + "not guess at a different tab."
                )
            case .unknown:
                explain(
                    "No terminal owns \(tty)",
                    "Nothing in that process's ancestry is a terminal vibra "
                    + "knows how to drive.\n\nvibra will not guess at a "
                    + "different tab."
                )
            }
        }
    }

    private func explain(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func dot(_ state: SessionState) -> String {
        switch state {
        case .working: "🔵"
        case .awaitingInput: "🟠"
        case .blocked: "🔴"
        case .stalled: "🟡"
        case .idle: "⚪️"
        }
    }

    private func stateText(_ state: SessionState) -> String {
        switch state {
        case .working: "working"
        case .awaitingInput: "your turn"
        case .blocked: "needs approval"
        case .stalled: "stalled"
        case .idle: "idle"
        }
    }

    @objc private func refreshNow() { Task { await store.requestRefresh() } }

    @objc private func showReport() { reportWindow.show() }
}
