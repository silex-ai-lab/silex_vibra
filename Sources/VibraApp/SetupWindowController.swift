import AppKit
import ServiceManagement
import VibraCore

/// The first-run check: what Vibra found, whether notifications work, and
/// whether to launch at login. Closing it counts as finishing it.
@MainActor
final class SetupWindowController: NSObject, RenderableWindow, NSWindowDelegate {
    private var window: NSWindow?
    private let sink: UserNotificationSink
    private let detections: () -> [AgentDetection]
    private let settings: any SettingsStore

    private let agentsLabel = NSTextField(wrappingLabelWithString: "")
    private let notificationLabel = NSTextField(wrappingLabelWithString: "")
    private let testResult = NSTextField(wrappingLabelWithString: "")
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch Vibra at login", target: nil, action: nil)
    private let loginResult = NSTextField(wrappingLabelWithString: "")
    private let enableButton = NSButton(title: "Enable Notifications", target: nil, action: nil)

    var onRendered: (() -> Void)?

    init(
        sink: UserNotificationSink = UserNotificationSink(),
        detections: @escaping () -> [AgentDetection] = AdapterRegistry.detections,
        settings: any SettingsStore = PreferencesStore()
    ) {
        self.sink = sink
        self.detections = detections
        self.settings = settings
    }

    var windowIsVisible: Bool { window?.isVisible ?? false }
    var windowFrame: NSRect { window?.frame ?? .zero }

    var renderedText: String {
        [
            "notifications: \(notificationLabel.stringValue)",
            "login item: \(SMAppService.mainApp.status.rawValue) \(loginResult.stringValue)",
            "complete: \(FirstRun.isComplete(in: settings))",
        ].joined(separator: "\n")
    }

    @discardableResult
    func snapshot(to url: URL) -> Bool {
        snapshotContent(of: window, to: url)
    }

    func show() {
        ensureWindow()
        agentsLabel.stringValue = detections()
            .map { "\($0.kind.displayName): \($0.isPresent ? "seen recently" : "no sessions yet")" }
            .joined(separator: "\n")
        refreshLoginState()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await refreshNotificationState()
            onRendered?()
        }
    }

    private func refreshNotificationState() async {
        let status = await sink.authorizationSummary()
        apply(status)
    }

    private func apply(_ status: NotificationAuthorization) {
        switch status {
        case .allowed:
            notificationLabel.stringValue = "Notifications are on."
            enableButton.isHidden = true
        case .notAsked:
            notificationLabel.stringValue = "Notifications are off. Vibra can ask macOS for permission."
            enableButton.isHidden = false
        case .denied:
            notificationLabel.stringValue = "macOS is not allowing notifications for this copy of Vibra. "
                + "The menu bar still shows everything a notification would say."
            enableButton.isHidden = true
        }
    }

    private func refreshLoginState() {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginCheckbox.state = .on
            loginResult.stringValue = ""
        case .requiresApproval:
            loginCheckbox.state = .on
            loginResult.stringValue = "Waiting for approval in System Settings › General › Login Items."
        default:
            loginCheckbox.state = .off
            loginResult.stringValue = ""
        }
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Vibra — setup"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()

        let title = NSTextField(labelWithString: "Vibra watches your coding agents on this Mac.")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let promise = NSTextField(wrappingLabelWithString:
            "No account, no API key, no hooks. Nothing leaves this Mac. "
            + "Use your agents as usual and their sessions appear in the menu bar.")
        promise.textColor = .secondaryLabelColor

        let agentsTitle = sectionTitle("Agents")
        let notificationsTitle = sectionTitle("Notifications")

        enableButton.target = self
        enableButton.action = #selector(enableNotifications)
        let testButton = NSButton(title: "Send Test", target: self, action: #selector(sendTest))
        let settingsButton = NSButton(title: "Open Notification Settings", target: self, action: #selector(openNotificationSettings))
        let buttons = NSStackView(views: [enableButton, testButton, settingsButton])
        buttons.spacing = 8

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        loginResult.textColor = .secondaryLabelColor
        testResult.textColor = .secondaryLabelColor

        let start = NSButton(title: "Start Using Vibra", target: self, action: #selector(finish))
        start.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            title, promise, agentsTitle, agentsLabel, notificationsTitle, notificationLabel,
            buttons, testResult, loginCheckbox, loginResult, start,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            promise.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            notificationLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            testResult.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            loginResult.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
        ])
        w.contentView = content
        window = w
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    @objc private func enableNotifications() {
        Task { @MainActor in
            apply(await sink.requestAuthorization())
        }
    }

    @objc private func sendTest() {
        Task { @MainActor in
            let accepted = await sink.deliverTest()
            testResult.stringValue = accepted
                ? "Sent. If no banner appeared, check System Settings › Notifications › Vibra."
                : "macOS would not take the notification. The menu bar still works."
            await refreshNotificationState()
        }
    }

    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        let wantsOn = loginCheckbox.state == .on
        do {
            if wantsOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginState()
        } catch {
            refreshLoginState()
            loginResult.stringValue = "macOS did not accept this. On a locally built copy this can fail; "
                + "use System Settings › General › Login Items instead."
        }
    }

    @objc private func finish() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        FirstRun.markComplete(in: settings)
    }
}
