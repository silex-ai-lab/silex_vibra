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
    private let notifier = Notifier()

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
        notifier.requestAuthorizationIfNeeded()

        store.onChange = { [weak self] previous, sessions in
            guard let self else { return }
            self.render(sessions)
            self.notchOverlay?.update(sessions: sessions)
            self.notifier.notifyIfNeeded(previous: previous, current: sessions)
        }
        render(store.sessions)
        store.start()
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
        let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        item.toolTip = "\(session.cwd)\n\(session.model ?? "unknown model")"
        return item
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

    @objc private func refreshNow() { store.refresh() }
}
