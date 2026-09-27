import AppKit
import VibraCore

/// The questions you asked, by day, searchable.
///
/// Read on demand when the window opens (like the usage report), held in
/// memory only while it is open, and released when it closes. Nothing is
/// written to disk. This window is the one place Vibra shows prompt text.
@MainActor
final class HistoryWindowController: NSObject, RenderableWindow, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate {

    private enum Row {
        case day(Date, Int)
        case question(QuestionRecord)
    }

    private var window: NSWindow?
    private let table = NSTableView()
    private let search = NSSearchField()
    private let agentPopup = NSPopUpButton()
    private let daysPopup = NSPopUpButton()
    private let status = NSTextField(labelWithString: "")

    private let adapters: [any AgentAdapter]
    /// The live session with this id, if there is one, for jump-on-open.
    private let liveSession: (String) -> Session?

    private var records: [QuestionRecord] = []
    private var loadedDays = 0
    private var rows: [Row] = []
    private var loadID = 0
    private var bytesRead = 0

    var onRendered: (() -> Void)?

    /// Agents whose history v1 reads. Stated in the window rather than
    /// implying the list is complete.
    private static let covered: [AgentKind] = [.claudeCode, .codex, .hermes]

    init(adapters: [any AgentAdapter], liveSession: @escaping (String) -> Session? = { _ in nil }) {
        self.adapters = adapters
        self.liveSession = liveSession
    }

    var windowIsVisible: Bool { window?.isVisible ?? false }
    var windowFrame: NSRect { window?.frame ?? .zero }

    /// Row count and day headers only - never question text - so the
    /// diagnostic that prints this cannot leak content.
    var renderedText: String {
        var lines = [status.stringValue]
        for row in rows {
            if case .day(let day, let count) = row {
                lines.append("\(Self.dayFormatter.string(from: day)) — \(count)")
            }
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func snapshot(to url: URL) -> Bool {
        snapshotContent(of: window, to: url)
    }

    func show() {
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        load()
    }

    // MARK: - Loading

    private var selectedDays: Int {
        HistoryIndex.allowedDays[max(daysPopup.indexOfSelectedItem, 0)]
    }

    private func load() {
        loadID += 1
        let id = loadID
        let days = selectedDays
        status.stringValue = "Reading the last \(days) day\(days == 1 ? "" : "s")…"
        let ingest = HistoryIngest(adapters: adapters)
        Task { [weak self] in
            let collected = await ingest.collect(windowDays: days)
            let bytes = await ingest.lastBytesRead
            await MainActor.run {
                guard let self, self.loadID == id, self.window?.isVisible == true else { return }
                self.records = collected
                self.loadedDays = days
                self.bytesRead = bytes
                self.applyFilters()
                self.onRendered?()
            }
        }
    }

    private func applyFilters() {
        let agentIndex = agentPopup.indexOfSelectedItem
        let agent = agentIndex > 0 ? Self.covered[agentIndex - 1] : nil
        let index = HistoryIndex.build(
            records, windowDays: loadedDays, now: Date(), keyword: search.stringValue, agent: agent)
        rows = index.days.flatMap { day in
            [Row.day(day.day, day.questions.count)] + day.questions.map(Row.question)
        }
        table.reloadData()
        let names = Self.covered.map(\.displayName).joined(separator: ", ")
        status.stringValue = "\(index.count) question\(index.count == 1 ? "" : "s")"
            + String(format: " · read %.1f MB", Double(bytesRead) / 1_048_576)
            + " · covers \(names) · nothing is saved"
    }

    // MARK: - Window

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Vibra — history"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()

        search.placeholderString = "Search questions and projects"
        search.target = self
        search.action = #selector(filtersChanged)

        agentPopup.addItems(withTitles: ["All agents"] + Self.covered.map(\.displayName))
        agentPopup.target = self
        agentPopup.action = #selector(filtersChanged)

        daysPopup.addItems(withTitles: HistoryIndex.allowedDays.map { "Last \($0) day\($0 == 1 ? "" : "s")" })
        daysPopup.selectItem(at: HistoryIndex.allowedDays.firstIndex(of: 7) ?? 0)
        daysPopup.target = self
        daysPopup.action = #selector(daysChanged)

        let bar = NSStackView(views: [search, agentPopup, daysPopup])
        bar.orientation = .horizontal
        bar.spacing = 8

        let column = NSTableColumn(identifier: .init("q"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.usesAutomaticRowHeights = false
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openRow)
        table.style = .plain

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [bar, scroll, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        for view in [bar, scroll, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        w.contentView = stack
        window = w
    }

    /// Releases the questions: they exist only while the window is open.
    func windowWillClose(_ notification: Notification) {
        loadID += 1
        records = []
        rows = []
        table.reloadData()
    }

    @objc private func filtersChanged() {
        applyFilters()
    }

    @objc private func daysChanged() {
        load()
    }

    /// Double-click: jump to the session if it is still live, otherwise put
    /// the full question on the pasteboard.
    @objc private func openRow() {
        let index = table.clickedRow
        guard rows.indices.contains(index), case .question(let q) = rows[index] else { return }
        if let session = liveSession(q.sessionID), case .jumped = TerminalJumper.jump(to: session) {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(q.text, forType: .string)
        status.stringValue = "Copied the question to the clipboard (its session is not live)."
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .day = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        switch rows[row] {
        case .day(let day, let count):
            label.stringValue = "\(Self.dayFormatter.string(from: day))  ·  \(count)"
            label.font = .boldSystemFont(ofSize: 12)
        case .question(let q):
            label.stringValue = "\(Self.timeFormatter.string(from: q.timestamp))   "
                + "\(q.agent.displayName) · \(q.project)   \(q.firstLine())"
            label.font = .systemFont(ofSize: 12)
            label.toolTip = q.text
        }
        return label
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
