import AppKit
import VibraCore

/// Owns the status item and renders the session list into its menu.
///
/// The status item title is deliberately terse: a glanceable count, not a
/// sentence. Detail belongs in the dropdown, where it costs the user a click
/// they chose to spend.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let store: SessionStore
    private let notchOverlay: NotchOverlay?
    private lazy var reportWindow = ReportWindowController(adapters: AdapterRegistry.all())
    private lazy var historyWindow = HistoryWindowController(
        adapters: AdapterRegistry.all(),
        liveSession: { [weak self] id in self?.store.sessions.first { $0.id == id } }
    )
    private lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController()
        controller.onChange = { [weak self] in
            Task { @MainActor in await self?.store.requestRefresh() }
        }
        return controller
    }()
    private let notificationSink = UserNotificationSink()
    private lazy var setupWindow: SetupWindowController = {
        SetupWindowController(sink: notificationSink, detections: AdapterRegistry.detections)
    }()
    private let evidenceIngest: EvidenceIngest
    private lazy var detailWindow = SessionDetailWindowController(
        onReturn: { [weak self] session in
            guard let self else { return }
            self.explainFailure(TerminalJumper.jump(to: session), for: session)
        },
        onHistory: { [weak self] session in
            self?.historyWindow.show(sessionID: session.id, notice: nil)
        },
        evidence: { [weak self] session in await self?.readEvidence(for: session) ?? nil }
    )
    private lazy var notifier = AttentionNotifier(sink: notificationSink)
    private let incidentStore = IncidentStore()
    private lazy var incidentMonitor = IncidentMonitor(
        adapters: AdapterRegistry.all(),
        store: incidentStore,
        deliver: { [weak self] notification in
            Task { @MainActor in self?.notificationSink.deliver(notification) }
        })
    private lazy var incidentsWindow = IncidentsWindowController(
        monitor: incidentMonitor,
        store: incidentStore,
        onJump: { [weak self] sessionID in self?.jumpToIncidentSession(sessionID) },
        onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.refreshIncidentCount() }
        })
    private var incidentTask: Task<Void, Never>?
    private var incidentReviewCount = 0
    private var hasBaseline = false

    init(store: SessionStore) {
        self.store = store
        self.evidenceIngest = EvidenceIngest(adapters: AdapterRegistry.all())
        // nil on a machine with no notch - the whole feature no-ops rather
        // than drawing a floating panel where no notch exists.
        self.notchOverlay = NotchOverlay.makeIfSupported()
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // Delivery is not guaranteed for an ad-hoc signed bundle, so a refusal
        // here must not be fatal - the menu bar still shows everything the
        // notification would have said. Until setup has run it owns the ask.
        if FirstRun.isComplete() {
            notificationSink.requestAuthorizationIfNeeded()
        }
        notificationSink.onClick { [weak self] sessionID, key in
            self?.jumpFromNotification(sessionID: sessionID, key: key)
        }

        startIncidentMonitor()

        store.onChange = { [weak self] previous, snapshot in
            guard let self else { return }
            let sessions = snapshot.sessions
            self.render(sessions)
            self.detailWindow.update(snapshot: snapshot)
            self.writeDebugDump(snapshot)
            // A health-only change says nothing about any session. Passing it
            // through would also spend the baseline below on an empty list.
            guard previous != sessions else { return }
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
            self.notificationSink.removeDelivered(
                except: self.notifier.outstandingKeys.union([IncidentMonitor.notificationKey]))
        }
        render(store.sessions)
        store.start()
        if !FirstRun.isComplete() { setupWindow.show() }
    }

    /// Rebuilt when the menu opens, so wait times are current then and a
    /// refresh does not rebuild a menu nobody is looking at.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    /// Env-guarded and content-free: see `SessionMenuModel.diagnosticLines`.
    private func writeDebugDump(_ snapshot: StatusSnapshot) {
        guard let path = ProcessInfo.processInfo.environment["VIBRA_DEBUG_MENU_DUMP"],
              !path.isEmpty else { return }
        let now = Date()
        let lines = SessionMenuModel.build(snapshot, now: now).diagnosticLines(snapshot, now: now)
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// `--menu-check`: builds the real menu, invokes its first Session Details
    /// item and reports whether the detail window opened for that session.
    func runMenuCheck() -> Bool {
        let menu = NSMenu()
        populate(menu)
        let details = menu.items.first { $0.title == Self.detailsTitle }?.submenu
        guard let details, details.numberOfItems > 0,
              let session = details.items[0].representedObject as? Session else {
            print("menu-check: no Session Details item")
            return false
        }
        details.performActionForItem(at: 0)
        let visible = detailWindow.windowIsVisible
        let matches = detailWindow.showing == session.key
        print("menu-check: details items \(details.numberOfItems), window visible \(visible), shows clicked session \(matches)")
        return visible && matches
    }

    /// Clears Vibra's own delivered notifications on the way out.
    ///
    /// A "waiting for you" banner that outlives the process is unactionable —
    /// the menu bar it points at is gone — so leaving it behind is noise the
    /// user has to dismiss by hand.
    func shutdown() {
        incidentTask?.cancel()
        notificationSink.withdraw(keys: [IncidentMonitor.notificationKey])
        notifier.withdrawAll()
    }

    private func render(_ sessions: [Session]) {
        statusItem?.button?.title = summaryTitle(sessions)
    }

    /// e.g. "Vibra 2▶ 1!"  - working count, then attention count.
    private func summaryTitle(_ sessions: [Session]) -> String {
        let working = sessions.filter { $0.state == .working }.count
        let attention = sessions.filter { $0.state.needsAttention }.count
        if sessions.isEmpty { return "Vibra" }
        var parts: [String] = []
        if working > 0 { parts.append("\(working)▶") }
        if attention > 0 { parts.append("\(attention)!") }
        return parts.isEmpty ? "Vibra" : parts.joined(separator: " ")
    }

    private static let detailsTitle = "Session Details"

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snapshot = store.snapshot
        let model = SessionMenuModel.build(snapshot, now: Date())
        let byKey = Dictionary(
            snapshot.sessions.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if let message = model.emptyMessage {
            let empty = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for notice in model.notices {
            let item = NSMenuItem(title: "⚠︎ \(notice)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if model.emptyMessage != nil || !model.notices.isEmpty { menu.addItem(.separator()) }

        for section in model.sections {
            switch section.kind {
            case .needsYou, .running:
                let name = section.kind == .needsYou ? "Needs You" : "Running"
                menu.addItem(sectionHeader("\(name) · \(section.rows.count)"))
                for row in section.rows { menu.addItem(item(for: row, in: byKey)) }
            case .recent:
                let holder = NSMenuItem(title: "Recent · \(section.rows.count)", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for row in section.rows { submenu.addItem(item(for: row, in: byKey)) }
                holder.submenu = submenu
                menu.addItem(holder)
            }
            menu.addItem(.separator())
        }

        if !model.detailRows.isEmpty {
            let holder = NSMenuItem(title: Self.detailsTitle, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for row in model.detailRows {
                submenu.addItem(item(for: row, in: byKey, action: #selector(openDetails(_:))))
            }
            holder.submenu = submenu
            menu.addItem(holder)
            menu.addItem(.separator())
        }

        let report = NSMenuItem(title: "Usage Report…", action: #selector(showReport), keyEquivalent: "u")
        report.target = self
        menu.addItem(report)
        let review = NSMenuItem(
            title: incidentReviewCount > 0 ? "Review Agent Activity… (\(incidentReviewCount))" : "Review Agent Activity…",
            action: #selector(showIncidents), keyEquivalent: "")
        review.target = self
        menu.addItem(review)
        let history = NSMenuItem(title: "History…", action: #selector(showHistory), keyEquivalent: "y")
        history.target = self
        menu.addItem(history)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let setup = NSMenuItem(title: "Setup…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Quit Vibra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    private func item(
        for row: MenuRow,
        in sessions: [SessionKey: Session],
        action explicit: Selector? = nil
    ) -> NSMenuItem {
        let session = sessions[row.key]
        let action = explicit ?? (row.click == .returnToSession
            ? #selector(jumpToSession(_:)) : #selector(openDetails(_:)))
        let item = NSMenuItem(
            title: session.map { "\(dot($0.state)) \(row.title)" } ?? row.title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = session
        item.toolTip = row.tooltip
        return item
    }

    private func readEvidence(for session: Session) async -> DeliveryEvidence? {
        await evidenceIngest.evidence(for: session)
    }

    @objc private func openDetails(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? Session else { return }
        // With no session to return to, its details are as far as you can go.
        if ReturnRoute.of(session) == .none { store.markHandled(session) }
        detailWindow.show(session: session, snapshot: store.snapshot)
    }

    /// Clicking a row focuses the terminal the session runs in.
    ///
    /// When that is not possible the reason is shown rather than silently
    /// doing nothing — most often the session lives in a multiplexer pane
    /// (tmux, screen, herdr), whose pty the terminal emulator never sees.
    @objc private func jumpToSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? Session else { return }
        let outcome = TerminalJumper.jump(to: session)
        if case .jumped = outcome { store.markHandled(session) }
        explainFailure(outcome, for: session)
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
        if key == IncidentMonitor.notificationKey {
            notificationSink.withdraw(keys: [key])
            incidentsWindow.show()
            return
        }
        // Gone from the snapshot: exited, or aged out. Nothing to jump to, and
        // nothing the notification says is still true.
        guard let session = store.sessions.first(where: { $0.id == sessionID }) else {
            notifier.dismiss(key: key)
            return
        }
        // An agent that publishes no session->process link (OpenCode, Hermes)
        // has nothing to return to, so the click shows what Vibra knows about
        // the session, and clears this and every other dead end beside it.
        guard ReturnRoute.of(session) != .none else {
            notifier.dismiss(key: key)
            _ = dismissDeadEndNotifications()
            store.markHandled(session)
            detailWindow.show(session: session, snapshot: store.snapshot)
            return
        }
        let outcome = TerminalJumper.jump(to: session)
        switch outcome {
        case .jumped:
            notifier.dismiss(key: key)
            store.markHandled(session)
        case .notLocatable, .noControllingTerminal:
            // By key, not by session: the clicked notification is removed even
            // when it was left behind by an earlier run and never tracked here.
            notifier.dismiss(key: key)
            _ = dismissDeadEndNotifications()
            explainFailure(outcome, for: session)
        case .sharedCodexServer, .notPermitted, .noTerminalOwnsTTY:
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
        for session: Session
    ) {
        switch outcome {
        case .jumped:
            return
        case .notLocatable:
            historyWindow.show(sessionID: session.id, notice:
                "This session's window is no longer reachable. Its available history is shown below.")
            Task { await store.requestRefresh() }
        case .noControllingTerminal:
            historyWindow.show(sessionID: session.id, notice:
                "Vibra couldn't find a window for this session. Its available history is shown below.")
        case .sharedCodexServer:
            historyWindow.show(sessionID: session.id, notice:
                "This session couldn't be opened in the Codex desktop app. Its available history is shown below.")
        case .notPermitted(let app):
            explain(
                "Vibra isn't allowed to control \(app)",
                "macOS refused the Apple Event. Focusing a tab means asking "
                + "\(app) which one owns the session's terminal, and that needs "
                + "Automation permission.\n\nSystem Settings → Privacy & Security "
                + "→ Automation → Vibra → enable \(app).\n\nIf Vibra isn't listed "
                + "there yet, it has never been able to ask — reinstall with "
                + "`make install` and try once more.\n\nNote: Vibra is ad-hoc "
                + "signed, so rebuilding it changes its identity and macOS may "
                + "ask again."
            )
        case .noTerminalOwnsTTY(let tty, let owner):
            switch owner {
            case .multiplexer("Orca"):
                explain(
                    "Orca didn't switch to \(tty)",
                    "\(tty) belongs to Orca, but Orca didn't accept this "
                    + "session's terminal handle. A session started before Orca "
                    + "last restarted can do this.\n\nvibra will not guess at a "
                    + "different tab."
                )
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
                    "Nothing in that process's ancestry is a terminal Vibra "
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

    @objc private func refreshNow() { Task { await store.requestRefresh() } }

    @objc private func showReport() { reportWindow.show() }
    @objc private func showHistory() { historyWindow.show() }
    @objc private func showIncidents() { incidentsWindow.show() }

    /// Replays recent transcripts once at launch, then reads only what changed.
    private func startIncidentMonitor() {
        let monitor = incidentMonitor
        // The poll runs on the monitor's own actor; only the refreshes touch
        // the main actor.
        incidentTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await monitor.poll()
                await self?.refreshIncidentCount()
                self?.incidentsWindow.refreshIfVisible()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func refreshIncidentCount() async {
        let rows = await incidentMonitor.rows()
        incidentReviewCount = rows.filter { $0.disposition == .open && $0.incident.kind.rule.severity == .review }.count
    }

    private func jumpToIncidentSession(_ sessionID: String) {
        guard let session = store.sessions.first(where: { $0.id == sessionID }) else { return }
        explainFailure(TerminalJumper.jump(to: session), for: session)
    }
    @objc private func showSettings() { settingsWindow.show() }
    @objc private func showSetup() { setupWindow.show() }
}
