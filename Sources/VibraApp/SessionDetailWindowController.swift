import AppKit
import VibraCore

/// What Vibra knows about one session, and every next step that exists for it.
/// Reads nothing from disk: it renders the snapshot the menu already has.
@MainActor
final class SessionDetailWindowController: NSObject, RenderableWindow {
    private var window: NSWindow?
    private let onReturn: (Session) -> Void
    private let onHistory: (Session) -> Void
    private var session: Session?
    private var model: SessionDetailModel?

    private let heading = NSTextField(labelWithString: "")
    private let grid = NSGridView(numberOfColumns: 2, rows: 0)
    private let returnButton = NSButton(title: "Return to Session", target: nil, action: nil)
    private let historyButton = NSButton(title: "View History", target: nil, action: nil)
    private let folderButton = NSButton(title: "Open Project Folder", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy Path", target: nil, action: nil)

    var onRendered: (() -> Void)?

    init(
        onReturn: @escaping (Session) -> Void,
        onHistory: @escaping (Session) -> Void
    ) {
        self.onReturn = onReturn
        self.onHistory = onHistory
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
        ].joined(separator: "\n")
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
        apply(session: session, snapshot: snapshot)
        present(session: session, model: model!)
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
        apply(session: session, snapshot: snapshot)
    }

    /// Keeps an open window true as the snapshot changes.
    func update(snapshot: StatusSnapshot) {
        guard windowIsVisible, let session else { return }
        let fresh = snapshot.sessions.first { $0.key == session.key } ?? session
        apply(session: fresh, snapshot: snapshot)
    }

    private func apply(session: Session, snapshot: StatusSnapshot) {
        self.session = session
        let model = SessionDetailModel.build(session: session, snapshot: snapshot, now: Date())
        self.model = model
        heading.stringValue = model.heading
        window?.title = "Vibra — \(model.agentName)"
        while grid.numberOfRows > 0 { grid.removeRow(at: 0) }
        let rows: [(String, String)] = [
            ("Agent", model.agentName),
            ("Branch", model.branch),
            ("State", model.stateLine),
            ("Why", model.evidenceLine),
            ("Last observed", model.lastObservedLine),
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

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
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
