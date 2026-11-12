import AppKit
import UniformTypeIdentifiers
import VibraCore

/// The human-in-the-loop half of incident monitoring: facts and guidance per
/// finding, the user's answer, and a local report draft the user sends.
@MainActor
final class IncidentsWindowController: NSObject, RenderableWindow, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let monitor: IncidentMonitor
    private let store: IncidentStore
    private let onJump: (String) -> Void
    private let onChange: () -> Void

    private var window: NSWindow?
    private let table = NSTableView()
    private let headline = NSTextField(labelWithString: "")
    private let coverage = NSTextField(wrappingLabelWithString: "")
    private let importStatus = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let importButton = NSButton(title: "Import Vendor Usage…", target: nil, action: nil)
    private let expectedButton = NSButton(title: "Expected", target: nil, action: nil)
    private let resolvedButton = NSButton(title: "Resolved", target: nil, action: nil)
    private let reopenButton = NSButton(title: "Reopen", target: nil, action: nil)
    private let jumpButton = NSButton(title: "Jump to Session", target: nil, action: nil)
    private let draftButton = NSButton(title: "Draft Report…", target: nil, action: nil)

    private var rows: [IncidentJSON.Row] = []
    private let importGate = ImportGate()
    private var draftWindow: NSWindow?
    private var draftText: NSTextView?
    private var draftIncident: Incident?

    var onRendered: (() -> Void)?
    var windowIsVisible: Bool { window?.isVisible ?? false }
    var windowFrame: NSRect { window?.frame ?? .zero }

    init(
        monitor: IncidentMonitor,
        store: IncidentStore,
        onJump: @escaping (String) -> Void,
        onChange: @escaping () -> Void = {}
    ) {
        self.monitor = monitor
        self.store = store
        self.onJump = onJump
        self.onChange = onChange
        super.init()
    }

    var renderedText: String {
        ([headline.stringValue, coverage.stringValue, importStatus.stringValue]
            + rows.map { row in
                "\(IncidentText.title(row.incident))  \(IncidentText.owner(row.incident))  \(row.disposition.state)"
            }
            + [detail.stringValue]).joined(separator: "\n")
    }

    @discardableResult
    func snapshot(to url: URL) -> Bool { snapshotContent(of: window, to: url) }

    func show() {
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { [weak self] in
            await self?.reload()
            self?.onRendered?()
        }
    }

    /// Keeps an open window current as the monitor finds more.
    func refreshIfVisible() {
        guard windowIsVisible else { return }
        Task { [weak self] in await self?.reload() }
    }

    private func reload() async {
        let selected = selectedRow?.incident.id
        rows = await monitor.rows()
        let open = rows.filter { $0.disposition == .open && $0.incident.kind.rule.severity == .review }.count
        headline.stringValue = open == 1 ? "1 item to review" : "\(open) items to review"
        var notes = [
            "Claude Code and Codex only. Credential reads are detected for named commands, not sed, awk, scripts or interpreters, and writes by the path as written.",
            "Stolen quota can be checked only for organization API usage, one key at a time. Pro, Max and ChatGPT plans appear in no file you can import.",
        ]
        if store.wasReset {
            notes.append("The saved answers could not be read and were reset. The old file was kept beside the new one.")
        }
        coverage.stringValue = notes.joined(separator: " ")
        table.reloadData()
        if let selected, let index = rows.firstIndex(where: { $0.incident.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !rows.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateDetail()
        onChange()
    }

    private var selectedRow: IncidentJSON.Row? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil
    }

    private func updateDetail() {
        guard let row = selectedRow else {
            detail.stringValue = rows.isEmpty ? "Nothing found in the last 7 days." : ""
            [expectedButton, resolvedButton, reopenButton, jumpButton, draftButton].forEach { $0.isEnabled = false }
            return
        }
        let incident = row.incident
        detail.stringValue = [
            IncidentText.title(incident),
            IncidentText.summary(row),
            IncidentText.fact(incident.detail),
            "Posture: \(incident.posture.rawValue)",
        ].joined(separator: "\n")
        let isOpen = row.disposition == .open
        expectedButton.isEnabled = isOpen
        resolvedButton.isEnabled = isOpen
        reopenButton.isEnabled = !isOpen
        draftButton.isEnabled = incident.kind.rule.route != .none
        jumpButton.isEnabled = incident.agent != nil
    }

    // MARK: Answers

    @objc private func markExpected() { answer(.expected(at: Date())) }
    @objc private func markResolved() { answer(.resolved(at: Date())) }
    @objc private func reopen() { answer(.open) }

    private func answer(_ disposition: Disposition) {
        guard let id = selectedRow?.incident.id else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.store.set(disposition, for: id)
            await self.reload()
        }
    }

    @objc private func jump() {
        guard let id = selectedRow?.incident.id else { return }
        Task { [weak self] in
            guard let self, let session = await self.monitor.rawSessionID(for: id) else { return }
            self.onJump(session)
        }
    }

    // MARK: Draft

    @objc private func openDraft() {
        guard let incident = selectedRow?.incident,
              let draft = VendorReport.draft(
                incident: incident,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString),
              let channel = VendorReport.channel(for: incident)
        else { return }
        draftIncident = incident

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        sheet.title = draft.subject
        sheet.isReleasedWhenClosed = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 300))
        text.isEditable = true
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = draft.body
        text.autoresizingMask = [.width]
        scroll.documentView = text

        let warning = NSTextField(wrappingLabelWithString: channel.warning + " Nothing leaves this Mac until you send it yourself.")
        var buttons: [NSView] = [
            button("Copy", #selector(copyDraft)),
            button("Open Email Draft", #selector(openEmail)),
            button(channel.title, #selector(openVendorPage)),
        ]
        if channel.securityPage != nil { buttons.append(button("Security Program", #selector(openSecurityPage))) }
        buttons.append(button("Mark as Reported", #selector(markReported)))
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal

        let stack = NSStackView(views: [scroll, warning, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        sheet.contentView = stack
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        draftWindow = sheet
        draftText = text
        window?.beginSheet(sheet)
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let item = NSButton(title: title, target: self, action: action)
        item.bezelStyle = .rounded
        return item
    }

    private func closeDraft() {
        guard let draftWindow else { return }
        window?.endSheet(draftWindow)
        self.draftWindow = nil
    }

    private var editedDraft: VendorDraft? {
        guard let draftWindow, let body = draftText?.string else { return nil }
        return VendorDraft(subject: draftWindow.title, body: body)
    }

    @objc private func copyDraft() {
        guard let draft = editedDraft else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(draft.subject)\n\n\(draft.body)", forType: .string)
    }

    @objc private func openEmail() {
        guard let draft = editedDraft, let url = VendorReport.mailtoURL(draft) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openVendorPage() {
        if let incident = draftIncident, let channel = VendorReport.channel(for: incident) {
            NSWorkspace.shared.open(channel.page)
        }
    }

    @objc private func openSecurityPage() {
        if let incident = draftIncident, let page = VendorReport.channel(for: incident)?.securityPage {
            NSWorkspace.shared.open(page)
        }
    }

    /// Only the user knows whether anything was sent.
    @objc private func markReported() {
        guard let id = draftIncident?.id else { return }
        closeDraft()
        Task { [weak self] in
            guard let self else { return }
            await self.store.set(.reported(at: Date()), for: id)
            await self.reload()
        }
    }

    // MARK: Import

    @objc private func chooseImport() {
        let alert = NSAlert()
        alert.messageText = "Import a usage file"
        alert.informativeText = """
        Vibra compares a usage file you fetched with the usage on this Mac. It never sees your key and makes no request.

        Fetch one API key's usage in your own terminal. One complete page holds at most 31 days:

        curl -gs "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=2026-11-01T00:00:00Z&limit=31&bucket_width=1d&api_key_ids[]=KEY_ID&group_by[]=api_key_id" -H "anthropic-version: 2026-10-21" -H "x-api-key: $ANTHROPIC_ADMIN_KEY" > usage.json

        curl -gs "https://api.openai.com/v1/organization/usage/completions?start_time=1793491200&limit=31&bucket_width=1d&api_key_ids=KEY_ID&group_by=api_key_id" -H "Authorization: Bearer $OPENAI_ADMIN_KEY" > usage.json

        Replace KEY_ID and the start date. The file must hold exactly one key and be a complete page.
        """
        alert.addButton(withTitle: "Choose File…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runImport(url)
    }

    private func runImport(_ url: URL) {
        let generation = importGate.advance()
        importButton.isEnabled = false
        importStatus.stringValue = "Reading local usage for the file's days…"
        let gate = importGate
        let monitor = self.monitor
        Task.detached(priority: .utility) { [weak self] in
            let outcome = await IncidentImport.run(url: url, now: Date())
            var applied = false
            if case .success(let result) = outcome {
                applied = await monitor.replaceVendorIncidents(
                    scope: result.scope, with: result.incidents, isCurrent: { gate.isCurrent(generation) })
            }
            await MainActor.run { self?.finishImport(outcome, applied: applied, generation: generation) }
        }
    }

    private func finishImport(_ outcome: Result<VendorReconciliation, IncidentImport.Failure>, applied: Bool, generation: Int) {
        guard importGate.isCurrent(generation) else { return }
        importButton.isEnabled = true
        switch outcome {
        case .success(let result) where applied:
            importStatus.stringValue =
                "\(result.incidents.count) unexplained days, \(result.unreconciled.count) days not comparable."
            Task { [weak self] in await self?.reload() }
        case .success:
            importStatus.stringValue = ""
        case .failure(let error):
            importStatus.stringValue = String(describing: error)
        }
    }

    /// A read in progress cannot be cancelled. Closing discards its result.
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        _ = importGate.advance()
        importButton.isEnabled = true
        importStatus.stringValue = ""
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let item = rows[row]
        let text: String
        switch id {
        case "when": text = item.incident.completedAt.formatted(date: .numeric, time: .shortened)
        case "who": text = IncidentText.owner(item.incident)
        case "what": text = IncidentText.title(item.incident)
        default: text = item.disposition.state
        }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateDetail() }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = "Vibra — agent activity"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()

        headline.font = .systemFont(ofSize: 15, weight: .semibold)
        coverage.font = .systemFont(ofSize: 11)
        coverage.textColor = .secondaryLabelColor
        importStatus.font = .systemFont(ofSize: 11)
        importStatus.textColor = .secondaryLabelColor

        for (id, heading, width) in [("when", "When", 130.0), ("who", "Agent", 90.0), ("what", "Finding", 390.0), ("state", "Answer", 70.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = heading
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        importButton.target = self
        importButton.action = #selector(chooseImport)
        expectedButton.target = self
        expectedButton.action = #selector(markExpected)
        resolvedButton.target = self
        resolvedButton.action = #selector(markResolved)
        reopenButton.target = self
        reopenButton.action = #selector(reopen)
        jumpButton.target = self
        jumpButton.action = #selector(jump)
        draftButton.target = self
        draftButton.action = #selector(openDraft)

        let top = NSStackView(views: [headline, NSView(), importButton])
        top.orientation = .horizontal
        let actions = NSStackView(views: [expectedButton, resolvedButton, reopenButton, jumpButton, draftButton])
        actions.orientation = .horizontal

        let stack = NSStackView(views: [top, coverage, importStatus, scroll, detail, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        w.contentView = stack
        let inner = stack.widthAnchor
        top.widthAnchor.constraint(equalTo: inner, constant: -28).isActive = true
        scroll.widthAnchor.constraint(equalTo: inner, constant: -28).isActive = true
        coverage.widthAnchor.constraint(equalTo: inner, constant: -28).isActive = true
        importStatus.widthAnchor.constraint(equalTo: inner, constant: -28).isActive = true
        detail.widthAnchor.constraint(equalTo: inner, constant: -28).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        window = w
    }
}

/// Reads a chosen usage file and reconciles it. Off the main thread, never on
/// the poll. The file is parsed in memory and not stored.
enum IncidentImport {
    enum Failure: Error, CustomStringConvertible {
        case unreadable
        case refused(VendorImportError)
        case noAdapter

        var description: String {
            switch self {
            case .unreadable: "That file could not be read."
            case .refused(let error): error.description
            case .noAdapter: "The matching agent is not available on this Mac."
            }
        }
    }

    static func run(url: URL, now: Date) async -> Result<VendorReconciliation, Failure> {
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        let file: VendorUsageFile
        do {
            file = try VendorUsage.parse(data, now: now)
        } catch let error as VendorImportError {
            return .failure(.refused(error))
        } catch {
            return .failure(.unreadable)
        }
        guard let oldest = file.oldestDay else {
            return .success(VendorReconciliation(incidents: [], unreconciled: []))
        }
        let agent: AgentKind = file.provider == .anthropic ? .claudeCode : .codex
        guard let adapter = AdapterRegistry.all().first(where: { $0.kind == agent }) else {
            return .failure(.noAdapter)
        }
        let ingest = ReportIngest(adapters: [adapter])
        let window = ReportWindow(now: now, days: VendorUsage.windowDays(oldest: oldest, now: now), calendar: .current)
        let input = await ingest.collect(window: window)
        let local = VendorUsage.localDays(from: input.samplesByAgent[agent] ?? [], provider: file.provider)
        return .success(VendorUsage.reconcile(file, local: local, now: now))
    }
}

/// Which import is still wanted. Read from the monitor's actor, so a close
/// that lands while the result is queued still discards it.
final class ImportGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    func advance() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }

    func isCurrent(_ value: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == value
    }
}
