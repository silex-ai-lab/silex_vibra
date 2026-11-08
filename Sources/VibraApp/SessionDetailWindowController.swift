import AppKit
import VibraCore

/// What Vibra knows about one session, and every next step that exists for it.
/// The snapshot is the menu's own. The one thing it reads is the "Code checks"
/// row, through the injected `readEvidence`, on open and then at most once a
/// minute while `lastActivity` keeps moving.
@MainActor
final class SessionDetailWindowController: NSObject, RenderableWindow {
    private var window: NSWindow?
    private let onReturn: (Session) -> Void
    private let onHistory: (Session) -> Void
    private var session: Session?
    private var model: SessionDetailModel?

    private let readEvidence: @MainActor (Session) async -> DeliveryEvidence?
    private enum EvidenceRead {
        case reading
        case finished(DeliveryEvidence?)
    }
    private var evidenceRead = EvidenceRead.reading
    private var evidenceTask: Task<Void, Never>?
    private var evidenceStartedAt: Date?
    private var evidenceActivity: Date?
    private static let evidenceRefreshInterval: TimeInterval = 60

    private let heading = NSTextField(labelWithString: "")
    private let grid = NSGridView(numberOfColumns: 2, rows: 0)
    private let returnButton = NSButton(title: "Return to Session", target: nil, action: nil)
    private let historyButton = NSButton(title: "View History", target: nil, action: nil)
    private let folderButton = NSButton(title: "Open Project Folder", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy Path", target: nil, action: nil)

    var onRendered: (() -> Void)?

    init(
        onReturn: @escaping (Session) -> Void,
        onHistory: @escaping (Session) -> Void,
        evidence: @escaping @MainActor (Session) async -> DeliveryEvidence?
    ) {
        self.onReturn = onReturn
        self.onHistory = onHistory
        self.readEvidence = evidence
    }

    var windowIsVisible: Bool { window?.isVisible ?? false }
    var windowFrame: NSRect { window?.frame ?? .zero }
    var showing: SessionKey? { session?.key }

    /// Which controls are offered, never session content, so the diagnostic
    /// that prints this cannot leak it.
    var renderedText: String {
        [
            "return: \(returnButton.isHidden ? "hidden" : returnButton.title) enabled=\(returnButton.isEnabled)",
            "history: \(historyButton.isHidden ? "hidden" : "shown")",
            "route: \(model.map { "\($0.returnRoute)" } ?? "none") live=\(model?.isLive ?? false)",
            "evidence: \(evidenceCaseName)",
            "grid: \(grid.numberOfRows) rows, \(grid.subviews.count) views",
        ].joined(separator: "\n")
    }

    private var evidenceCaseName: String {
        guard model?.evidenceAvailable == true else { return "hidden" }
        switch evidenceRead {
        case .reading: return "checking"
        case .finished(let evidence): return evidence?.caseName ?? "unreadable"
        }
    }

    /// True once the "Code checks" row shows its real text, or is hidden.
    var evidenceSettled: Bool {
        guard model?.evidenceAvailable == true else { return true }
        if case .finished = evidenceRead { return true }
        return false
    }

    @discardableResult
    func snapshot(to url: URL) -> Bool {
        snapshotContent(of: window, to: url)
    }

    func show() {
        guard let session, let model else { return }
        present(session: session, model: model)
    }

    func show(session: Session, snapshot: StatusSnapshot) {
        ensureWindow()
        open(session: session, snapshot: snapshot)
        present(session: session, model: model!)
    }

    /// A session being opened shows "Checking…" until its own read returns, so
    /// the row never carries another session's answer.
    private func open(session: Session, snapshot: StatusSnapshot) {
        if self.session?.key != session.key {
            evidenceTask?.cancel()
            evidenceTask = nil
            evidenceRead = .reading
        }
        apply(session: session, snapshot: snapshot)
        startEvidenceRead(for: session)
    }

    private func startEvidenceRead(for session: Session) {
        guard evidenceTask == nil, model?.evidenceAvailable == true else { return }
        evidenceActivity = session.lastActivity
        evidenceStartedAt = Date()
        let key = session.key
        evidenceTask = Task { [readEvidence] in
            let evidence = await readEvidence(session)
            self.finishEvidenceRead(evidence, for: key)
        }
    }

    private func finishEvidenceRead(_ evidence: DeliveryEvidence?, for key: SessionKey) {
        guard session?.key == key else { return }
        evidenceTask = nil
        evidenceRead = .finished(evidence)
        renderRows()
    }

    private func refreshEvidenceIfDue(_ session: Session) {
        guard evidenceTask == nil, case .finished = evidenceRead,
              session.lastActivity != evidenceActivity,
              Date().timeIntervalSince(evidenceStartedAt ?? .distantPast) >= Self.evidenceRefreshInterval
        else { return }
        startEvidenceRead(for: session)
    }

    private func present(session: Session, model: SessionDetailModel) {
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onRendered?()
    }

    /// Prepares the window without showing it, for the `--show-detail` diagnostic.
    func prepare(session: Session, snapshot: StatusSnapshot) {
        ensureWindow()
        open(session: session, snapshot: snapshot)
    }

    /// Keeps an open window true as the snapshot changes.
    func update(snapshot: StatusSnapshot) {
        guard windowIsVisible, let session else { return }
        let fresh = snapshot.sessions.first { $0.key == session.key } ?? session
        apply(session: fresh, snapshot: snapshot)
        refreshEvidenceIfDue(fresh)
    }

    private func apply(session: Session, snapshot: StatusSnapshot) {
        self.session = session
        let model = SessionDetailModel.build(session: session, snapshot: snapshot, now: Date())
        self.model = model
        heading.stringValue = model.heading
        window?.title = "Vibra — \(model.agentName)"
        renderRows()
        switch model.returnRoute {
        case .none:
            returnButton.isHidden = true
        case .attempt:
            returnButton.isHidden = false
            returnButton.title = "Return to Session"
        case .focusApp:
            returnButton.isHidden = false
            returnButton.title = "Open \(model.agentName)"
        }
        returnButton.isEnabled = model.isLive
        historyButton.isHidden = !model.historyAvailable
    }

    private func renderRows() {
        guard let model else { return }
        // removeRow leaves the cells' views on screen, so they must go first.
        while grid.numberOfRows > 0 {
            let row = grid.row(at: 0)
            for index in 0..<row.numberOfCells { row.cell(at: index).contentView?.removeFromSuperview() }
            grid.removeRow(at: 0)
        }
        var rows: [(String, String)] = [
            ("Agent", model.agentName),
            ("Branch", model.branch),
            ("State", model.stateLine),
            ("Why", model.evidenceLine),
            ("Last observed", model.lastObservedLine),
        ]
        if model.evidenceAvailable {
            switch evidenceRead {
            case .reading: rows.append(("Code checks", "Checking…"))
            case .finished(let evidence):
                rows.append(("Code checks", evidence?.line(now: Date()) ?? "Couldn't read this session's transcript."))
            }
        }
        rows += [
            ("Data source", model.healthLine),
            ("Tokens", model.tokensLine),
            ("Project", model.cwd),
        ]
        for (name, value) in rows {
            let label = NSTextField(labelWithString: name)
            label.textColor = .secondaryLabelColor
            let field = NSTextField(wrappingLabelWithString: value)
            field.isSelectable = true
            grid.addRow(with: [label, field])
        }
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.center()

        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 380
        grid.rowSpacing = 6
        grid.columnSpacing = 10

        for (button, selector) in [
            (returnButton, #selector(returnToSession)),
            (historyButton, #selector(viewHistory)),
            (folderButton, #selector(openFolder)),
            (copyButton, #selector(copyPath)),
        ] as [(NSButton, Selector)] {
            button.target = self
            button.action = selector
        }
        let buttons = NSStackView(views: [returnButton, historyButton, folderButton, copyButton])
        buttons.spacing = 8

        let stack = NSStackView(views: [heading, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        window = w
    }

    @objc private func returnToSession() {
        guard let session else { return }
        onReturn(session)
    }

    @objc private func viewHistory() {
        guard let session else { return }
        onHistory(session)
    }

    @objc private func openFolder() {
        guard let session else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
    }

    @objc private func copyPath() {
        guard let session else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.cwd, forType: .string)
    }
}
