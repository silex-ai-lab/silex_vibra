import AppKit
import VibraCore

private extension NSImage {
    /// An SF Symbol for the given name, nil when the name does not resolve —
    /// so every caller keeps working as a plain text-only control. The
    /// description carries the control's title, so the picture is never
    /// unnamed to VoiceOver. Symbols come back as templates: they follow
    /// light/dark beside the label they sit with.
    static func vibraSymbol(_ name: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }
}

/// The questions you asked, by day, searchable.
///
/// Read on demand when the window opens (like the usage report), held in
/// memory only while it is open, and released when it closes. Nothing is
/// written to disk. This window is the one place Vibra shows prompt text.
/// The window the controller owns, so key handling sits at window scope:
/// decided before the first responder sees anything, the table and the detail
/// text keep every key they already own.
private final class HistoryWindow: NSWindow {
    /// Returns true when the controller consumed the event.
    var keyHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

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
    private let copyRowsButton = NSButton()
    private let status = NSTextField(labelWithString: "")
    private let navigationNotice = NSTextField(wrappingLabelWithString: "")
    private let allSessionsButton = NSButton(title: "All sessions", target: nil, action: nil)
    private var focusedSessionID: String?
    private let emptyLabel = NSTextField(labelWithString: "No questions match.")
    private let detailMeta = NSTextField(labelWithString: "")
    private let detailText = NSTextView()
    private let detailPlaceholder = NSTextField(labelWithString: "Select a question to read.")
    private let copyDetailButton = NSButton()
    private let pathLabel = NSTextField(labelWithString: "")
    private let copyPathButton = NSButton()
    private let openPathButton = NSButton()
    private let pathLine = NSStackView()
    private let sectionsStack = NSStackView()
    private let tasksWrapper = NSStackView()
    private let timelineWrapper = NSStackView()
    private let tasksHeader = NSButton()
    private let timelineHeader = NSButton()
    private let tasksTitle = NSTextField(labelWithString: "Tasks")
    private let timelineTitle = NSTextField(labelWithString: "Timeline")
    private let tasksText = NSTextView()
    private let timelineText = NSTextView()
    private let tasksScroll = NSScrollView()
    private let timelineScroll = NSScrollView()

    private let adapters: [any AgentAdapter]
    /// The live session with this id, if there is one, for jump-on-open.
    private let liveSession: (String) -> Session?

    private var records: [QuestionRecord] = []
    private var loadedDays = 0
    private var rows: [Row] = []
    private var loadID = 0
    /// Guards the on-demand detail read: a fast selection change must never
    /// paint the previous question's tasks.
    private var detailID = 0
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

    func show() { show(sessionID: nil, notice: nil) }

    func show(sessionID: String?, notice: String?) {
        ensureWindow()
        focusedSessionID = sessionID
        navigationNotice.stringValue = notice ?? ""
        navigationNotice.isHidden = notice == nil
        allSessionsButton.isHidden = sessionID == nil
        if let sessionID {
            window?.title = "Vibra — session \(sessionID.prefix(8))"
            search.stringValue = ""
            agentPopup.selectItem(at: 0)
            daysPopup.selectItem(at: HistoryIndex.allowedDays.count - 1)
        } else {
            window?.title = "Vibra — history"
        }
        // Do not leave the previous session's questions visible while the
        // asynchronous reload is running after a second session click.
        table.deselectAll(nil)
        applyFilters()
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
        // One build, without the agent filter: it is the single source for the
        // popup counts and for the rows, which are its questions narrowed to
        // the selected agent. Counts therefore never depend on the selection.
        let base = HistoryIndex.build(
            records, windowDays: loadedDays, now: Date(), keyword: search.stringValue,
            sessionID: focusedSessionID)
        var perAgent: [AgentKind: Int] = [:]
        for day in base.days {
            for question in day.questions { perAgent[question.agent, default: 0] += 1 }
        }
        agentPopup.item(at: 0)?.title = "All agents (\(base.count))"
        for (offset, kind) in Self.covered.enumerated() {
            agentPopup.item(at: offset + 1)?.title = "\(kind.displayName) (\(perAgent[kind] ?? 0))"
        }

        rows = []
        var displayed = 0
        for day in base.days {
            let questions = agent == nil
                ? day.questions
                : day.questions.filter { $0.agent == agent }
            guard !questions.isEmpty else { continue }
            displayed += questions.count
            rows.append(.day(day.day, questions.count))
            rows.append(contentsOf: questions.map(Row.question))
        }
        table.reloadData()
        if focusedSessionID != nil,
           let first = rows.firstIndex(where: { if case .question = $0 { return true }; return false }) {
            table.selectRowIndexes(IndexSet(integer: first), byExtendingSelection: false)
        }
        emptyLabel.isHidden = displayed > 0
        updateDetail()
        let names = Self.covered.map(\.displayName).joined(separator: ", ")
        status.stringValue = "\(displayed) question\(displayed == 1 ? "" : "s")"
            + String(format: " · read %.1f MB", Double(bytesRead) / 1_048_576)
            + " · covers \(names) · nothing is saved"
    }

    // MARK: - Window

    private func ensureWindow() {
        guard window == nil else { return }
        let w = HistoryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Vibra — history"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
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

        copyRowsButton.title = "Copy"
        copyRowsButton.image = NSImage.vibraSymbol("doc.on.doc", description: "Copy")
        copyRowsButton.imagePosition = .imageLeading
        copyRowsButton.target = self
        copyRowsButton.action = #selector(copyRows)

        allSessionsButton.target = self
        allSessionsButton.action = #selector(showAllSessions)
        allSessionsButton.isHidden = true
        navigationNotice.isHidden = true
        navigationNotice.textColor = .secondaryLabelColor
        let bar = NSStackView(views: [search, agentPopup, daysPopup, copyRowsButton, allSessionsButton])
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

        // Sibling overlay, pinned above the scroll view - never a row of the
        // table itself, so it never scrolls away with the document.
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true
        let leftPane = NSView()
        leftPane.addSubview(scroll)
        leftPane.addSubview(emptyLabel)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: leftPane.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: leftPane.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: leftPane.topAnchor, constant: 12),
        ])

        // Detail pane: meta line, the stored text read in place, and a Copy
        // button. The text view is selectable but never editable.
        detailText.isEditable = false
        detailText.isSelectable = true
        detailText.font = .systemFont(ofSize: 13)
        detailText.minSize = NSSize(width: 0, height: 0)
        detailText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detailText.isVerticallyResizable = true
        detailText.isHorizontallyResizable = false
        detailText.autoresizingMask = [.width]
        detailText.textContainer?.widthTracksTextView = true

        let detailScroll = NSScrollView()
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.documentView = detailText

        detailMeta.textColor = .secondaryLabelColor
        detailMeta.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailMeta.lineBreakMode = .byTruncatingTail
        detailMeta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copyDetailButton.title = "Copy"
        copyDetailButton.image = NSImage.vibraSymbol("doc.on.doc", description: "Copy")
        copyDetailButton.imagePosition = .imageLeading
        copyDetailButton.isEnabled = false
        copyDetailButton.target = self
        copyDetailButton.action = #selector(copyDetail)

        detailPlaceholder.textColor = .secondaryLabelColor

        // Header: meta line with its Copy button, then the origin-file row —
        // hidden as one unit when the record came from no file, so the pane
        // collapses back to exactly what wave 1 shipped.
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathLabel.lineBreakMode = .byTruncatingTail
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copyPathButton.title = "Copy Path"
        copyPathButton.image = NSImage.vibraSymbol("link", description: "Copy Path")
        copyPathButton.imagePosition = .imageLeading
        copyPathButton.isEnabled = false
        copyPathButton.target = self
        copyPathButton.action = #selector(copyPath)
        openPathButton.title = "Open"
        openPathButton.image = NSImage.vibraSymbol("arrow.up.forward", description: "Open")
        openPathButton.imagePosition = .imageLeading
        openPathButton.isEnabled = false
        openPathButton.target = self
        openPathButton.action = #selector(openPath)
        pathLine.orientation = .horizontal
        pathLine.spacing = 8
        pathLine.alignment = .centerY
        pathLine.isHidden = true
        pathLine.addArrangedSubview(pathLabel)
        pathLine.addArrangedSubview(copyPathButton)
        pathLine.addArrangedSubview(openPathButton)

        let metaLine = NSStackView(views: [detailMeta, copyDetailButton])
        metaLine.orientation = .horizontal
        metaLine.spacing = 8
        metaLine.alignment = .centerY
        let header = NSStackView(views: [metaLine, pathLine])
        header.orientation = .vertical
        header.spacing = 6

        // Tasks and timeline: two disclosure sections under the question
        // text, collapsed until asked for, each bounded to a fixed height and
        // hidden as one unit when the selection carries no detail source.
        for (button, title) in [(tasksHeader, "Tasks"), (timelineHeader, "Timeline")] {
            button.title = title
            button.bezelStyle = .disclosure   // unbezeled triangle
            button.setButtonType(.toggle)     // state: .on = expanded
            button.target = self
            button.action = #selector(toggleSection(_:))
            button.state = .off
        }
        // The disclosure bezel sizes to the triangle alone, so the visible
        // word sits beside it; the button keeps its title for accessibility
        // and for anyone matching on it. The symbol goes between triangle and
        // word as its own view — the bezel must not carry an image, its cell
        // draws the triangle.
        for title in [tasksTitle, timelineTitle] {
            title.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        func sectionIcon(_ name: String, _ description: String) -> NSImageView {
            let view = NSImageView()
            view.image = NSImage.vibraSymbol(name, description: description)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
            return view
        }
        let tasksRow = NSStackView(views: [
            tasksHeader, sectionIcon("checklist", "Tasks"), tasksTitle,
        ])
        tasksRow.orientation = .horizontal
        tasksRow.spacing = 4
        tasksRow.alignment = .centerY
        let timelineRow = NSStackView(views: [
            timelineHeader, sectionIcon("clock", "Timeline"), timelineTitle,
        ])
        timelineRow.orientation = .horizontal
        timelineRow.spacing = 4
        timelineRow.alignment = .centerY
        for (scroll, text) in [(tasksScroll, tasksText), (timelineScroll, timelineText)] {
            text.isEditable = false
            text.isSelectable = true
            text.font = .systemFont(ofSize: 12)
            text.minSize = NSSize(width: 0, height: 0)
            text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            scroll.documentView = text
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        }
        tasksScroll.isHidden = true
        timelineScroll.isHidden = true
        tasksWrapper.orientation = .vertical
        tasksWrapper.spacing = 4
        tasksWrapper.alignment = .leading
        tasksWrapper.addArrangedSubview(tasksRow)
        tasksWrapper.addArrangedSubview(tasksScroll)
        timelineWrapper.orientation = .vertical
        timelineWrapper.spacing = 4
        timelineWrapper.alignment = .leading
        timelineWrapper.addArrangedSubview(timelineRow)
        timelineWrapper.addArrangedSubview(timelineScroll)
        sectionsStack.orientation = .vertical
        sectionsStack.spacing = 6
        sectionsStack.alignment = .leading
        sectionsStack.addArrangedSubview(tasksWrapper)
        sectionsStack.addArrangedSubview(timelineWrapper)
        // Alignment pins each child's leading edge only; without the trailing
        // pins the wrappers (and their text scrolls) collapse to intrinsic
        // width instead of spanning the pane.
        tasksWrapper.trailingAnchor.constraint(equalTo: sectionsStack.trailingAnchor)
            .isActive = true
        timelineWrapper.trailingAnchor.constraint(equalTo: sectionsStack.trailingAnchor)
            .isActive = true
        tasksScroll.trailingAnchor.constraint(equalTo: tasksWrapper.trailingAnchor)
            .isActive = true
        timelineScroll.trailingAnchor.constraint(equalTo: timelineWrapper.trailingAnchor)
            .isActive = true
        tasksWrapper.isHidden = true
        timelineWrapper.isHidden = true

        let detailPane = NSView()
        detailPane.addSubview(header)
        detailPane.addSubview(detailScroll)
        detailPane.addSubview(sectionsStack)
        detailPane.addSubview(detailPlaceholder)
        for view in [header, detailScroll, sectionsStack, detailPlaceholder] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: detailPane.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: detailPane.trailingAnchor, constant: -12),
            detailScroll.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: 12),
            detailScroll.trailingAnchor.constraint(equalTo: detailPane.trailingAnchor, constant: -12),
            detailScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            // The sections stack collapses to zero when hidden, so these two
            // leave the text scroll exactly where wave 1 put it.
            detailScroll.bottomAnchor.constraint(equalTo: sectionsStack.topAnchor, constant: -8),
            sectionsStack.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: 12),
            sectionsStack.trailingAnchor.constraint(equalTo: detailPane.trailingAnchor, constant: -12),
            sectionsStack.bottomAnchor.constraint(equalTo: detailPane.bottomAnchor, constant: -4),
            detailPlaceholder.centerXAnchor.constraint(equalTo: detailScroll.centerXAnchor),
            detailPlaceholder.centerYAnchor.constraint(equalTo: detailScroll.centerYAnchor),
        ])

        let split = NSSplitView()
        split.dividerStyle = .thin
        // Vertical divider: list on the left, detail pane on the right.
        split.isVertical = true
        split.addSubview(leftPane)
        split.addSubview(detailPane)
        leftPane.frame = NSRect(x: 0, y: 0, width: 560, height: 500)
        detailPane.frame = NSRect(x: 561, y: 0, width: 395, height: 500)

        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [bar, navigationNotice, split, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        for view in [bar, navigationNotice, split, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        w.contentView = stack
        window = w
    }

    /// Releases the questions: they exist only while the window is open, and a
    /// re-show must never present yesterday's detail text.
    func windowWillClose(_ notification: Notification) {
        loadID += 1
        records = []
        rows = []
        table.reloadData()
        table.deselectAll(nil)
        updateDetail()
    }

    @objc private func filtersChanged() {
        applyFilters()
    }

    @objc private func showAllSessions() { show() }

    @objc private func daysChanged() {
        load()
    }

    // MARK: - Detail pane

    private var selectedQuestion: QuestionRecord? {
        let index = table.selectedRow
        guard rows.indices.contains(index), case .question(let question) = rows[index]
        else { return nil }
        return question
    }

    /// Syncs the detail pane to the current selection: the stored text of the
    /// selected question, or the placeholder when a day header (or nothing)
    /// is selected. The path row appears only when the record has a file.
    private func updateDetail() {
        if let question = selectedQuestion {
            let session = question.sessionID.isEmpty
                ? ""
                : " · session \(String(question.sessionID.prefix(8)))"
            detailMeta.stringValue = "\(Self.timeFormatter.string(from: question.timestamp))"
                + " · \(question.agent.displayName) · \(question.project)" + session
            // A tail-truncated id in the line would be useless; the tooltip
            // carries it whole (the path's file name has it too).
            detailMeta.toolTip = question.sessionID.isEmpty ? nil : "session \(question.sessionID)"
            detailText.string = question.text
            fit(detailText)
            detailPlaceholder.isHidden = true
            copyDetailButton.isEnabled = true
            if let path = question.originFile {
                pathLabel.stringValue = path
                pathLabel.toolTip = path
                copyPathButton.isEnabled = true
                openPathButton.isEnabled = FileManager.default.fileExists(atPath: path)
                pathLine.isHidden = false
            } else {
                pathLabel.stringValue = ""
                pathLabel.toolTip = nil
                copyPathButton.isEnabled = false
                openPathButton.isEnabled = false
                pathLine.isHidden = true
            }
        } else {
            detailMeta.stringValue = ""
            detailMeta.toolTip = nil
            detailText.string = ""
            detailPlaceholder.isHidden = false
            copyDetailButton.isEnabled = false
            pathLabel.stringValue = ""
            pathLabel.toolTip = nil
            copyPathButton.isEnabled = false
            openPathButton.isEnabled = false
            pathLine.isHidden = true
        }
        loadDetailSections()
    }

    // MARK: - Tasks and timeline (on demand)

    /// Clears the sections, then reads the selected question's slice in the
    /// background — only when this selection has a detail source at all.
    /// Opening the window reads nothing for this; only a selection does.
    private func loadDetailSections() {
        detailID += 1
        let id = detailID
        tasksText.string = ""
        timelineText.string = ""
        tasksWrapper.isHidden = true
        timelineWrapper.isHidden = true
        guard let question = selectedQuestion,
              HistoryDetail.supports(agent: question.agent),
              let path = question.originFile
        else { return }
        let from = question.timestamp
        let to = sliceEnd(for: question)
        let sessionID = question.sessionID
        Task { [weak self] in
            let detail = await Task.detached(priority: .userInitiated) {
                HistoryDetail.extract(path: path, from: from, to: to)
            }.value
            guard let self, self.detailID == id,
                  let current = self.selectedQuestion,
                  current.sessionID == sessionID, current.timestamp == from
            else { return }
            if let detail {
                self.renderSections(detail)
            }
        }
    }

    /// The next question of the same session, so a slice stops where the
    /// following question begins; nil means open-ended (last question).
    private func sliceEnd(for question: QuestionRecord) -> Date? {
        records
            .filter { $0.sessionID == question.sessionID && $0.timestamp > question.timestamp }
            .map(\.timestamp)
            .min()
    }

    /// Sizes a read-only text view to its content. NSTextView only grows the
    /// frame while editing, so a programmatic `string = …` would otherwise
    /// keep the old (one-line) height and clip everything past it. The width
    /// comes from the layout position given, because a hidden scroll inside a
    /// collapsed stack has no usable size yet.
    private func fit(_ text: NSTextView, width: CGFloat, minViewport: CGFloat) {
        guard width > 1, let tc = text.textContainer, let lm = text.layoutManager
        else { return }
        text.setFrameSize(NSSize(width: width, height: text.frame.height))
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height + 4
        text.setFrameSize(NSSize(width: width, height: max(used, minViewport)))
    }

    private func fit(_ text: NSTextView) {
        guard let scroll = text.enclosingScrollView else { return }
        fit(text, width: scroll.contentSize.width, minViewport: scroll.contentSize.height)
    }

    private func renderSections(_ detail: HistoryDetail) {
        let tasks = detail.tasks.map { task in
            let symbol: String
            switch task.status {
            case .completed: symbol = "✓"
            case .inProgress: symbol = "◐"
            case .pending: symbol = "○"
            case .unknown: symbol = "·"
            }
            return "\(symbol) · \(task.text)"
        } + (detail.tasksTruncated ? ["…"] : [])
        tasksText.string = tasks.isEmpty ? "No tasks detected." : tasks.joined(separator: "\n")

        let events = detail.timeline.map {
            "\(Self.timeFormatter.string(from: $0.at))  ·  \($0.name)"
        } + (detail.timelineTruncated ? ["…"] : [])
        timelineText.string = events.isEmpty ? "No timeline events." : events.joined(separator: "\n")
        // The wrappers may still be collapsed here; the stack's own width is
        // the pane's and is valid either way.
        fit(tasksText, width: sectionsStack.bounds.width, minViewport: 120)
        fit(timelineText, width: sectionsStack.bounds.width, minViewport: 120)

        tasksWrapper.isHidden = false
        timelineWrapper.isHidden = false
    }

    @objc private func toggleSection(_ sender: NSButton) {
        let content = sender === tasksHeader ? tasksScroll : timelineScroll
        content.isHidden = sender.state == .off
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDetail()
    }

    /// Copy button: the selected question's text.
    @objc private func copyDetail() {
        guard let question = selectedQuestion else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(question.text, forType: .string)
        status.stringValue = liveSession(question.sessionID) != nil
            ? "Copied the question to the clipboard."
            : "Copied the question to the clipboard (its session is not live)."
    }

    /// Copy Path button: the transcript's absolute path — a name of a file the
    /// reader already owns, never a line of it.
    @objc private func copyPath() {
        guard let path = selectedQuestion?.originFile else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        status.stringValue = "Copied the path to the clipboard."
    }

    /// Open button: hand the path to the system. No shell, no editor choice
    /// Vibra invents; disabled in the UI when the file is already gone.
    @objc private func openPath() {
        guard let path = selectedQuestion?.originFile,
              FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Copy button: every visible question row as tab-separated fields, in
    /// display order. Nothing touches disk.
    @objc private func copyRows() {
        let lines = rows.compactMap { row -> String? in
            guard case .question(let question) = row else { return nil }
            return "\(Self.timeFormatter.string(from: question.timestamp))"
                + "\t\(question.agent.displayName)"
                + "\t\(question.project)"
                + "\t\(question.firstLine())"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        status.stringValue = "Copied \(lines.count) row\(lines.count == 1 ? "" : "s") to the clipboard."
    }

    /// Double-click: jump to the session if it is still live, otherwise put
    /// the full question on the pasteboard.
    @objc private func openRow() {
        activate(row: table.clickedRow)
    }

    // MARK: - Keyboard

    /// ⌘F focus search · ⌘⇧C copy visible rows · ⌘J jump to the selection ·
    /// Esc clear search. Window-local only: nothing here registers anywhere
    /// else, and unknown keys fall through to the responder chain untouched.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.keyCode == 53 {  // Esc: unmodified, characters are empty
            guard !search.stringValue.isEmpty else { return false }
            search.stringValue = ""
            applyFilters()
            return true
        }
        let mods = event.modifierFlags.intersection([.command, .shift])
        guard mods == .command || mods == [.command, .shift],
              let char = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        switch (char, mods) {
        case ("f", .command):
            window?.makeFirstResponder(search)
            return true
        case ("c", [.command, .shift]):
            copyRows()
            return true
        case ("j", .command):
            activate(row: table.selectedRow)
            return true
        default:
            return false
        }
    }

    /// One path for double-click and ⌘J: jump if the session is still live,
    /// otherwise keep the question visible without changing the clipboard.
    private func activate(row index: Int) {
        guard rows.indices.contains(index), case .question(let q) = rows[index] else { return }
        if let session = liveSession(q.sessionID), case .jumped = TerminalJumper.jump(to: session) {
            return
        }
        status.stringValue = "Couldn't open this session's window. You can read the question here or use Copy."
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
