import AppKit
import VibraCore

/// Three numbers: when a mid-turn session counts as stalled, when an
/// unanswered "your turn" fades to idle, and how far back the menu looks.
///
/// Each change is saved at once to the `ai.silexlab.vibra` preferences
/// domain, and `onChange` asks the store to refresh, so it applies without a
/// relaunch.
@MainActor
final class SettingsWindowController: NSObject, RenderableWindow {
    private var window: NSWindow?
    private let store: any SettingsStore
    private var rows: [Row] = []
    var onChange: (@MainActor () -> Void)?
    var onRendered: (() -> Void)?

    /// One setting's controls. The field and stepper show `unit`s; storage
    /// is seconds.
    private struct Row {
        let limit: VibraSettings.Limit
        let unit: Double
        let field: NSTextField
        let stepper: NSStepper
    }

    init(store: any SettingsStore = PreferencesStore()) {
        self.store = store
    }

    func show() {
        ensureWindow()
        load()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onRendered?()
    }

    var windowIsVisible: Bool { window?.isVisible ?? false }
    var windowFrame: NSRect { window?.frame ?? .zero }

    var renderedText: String {
        rows.map { "\($0.limit.key)=\($0.field.stringValue)" }.joined(separator: "\n")
    }

    @discardableResult
    func snapshot(to url: URL) -> Bool {
        snapshotContent(of: window, to: url)
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Vibra — settings"
        w.isReleasedWhenClosed = false
        w.center()

        let specs: [(VibraSettings.Limit, String, Double, String)] = [
            (VibraSettings.stallThreshold, "Mark a mid-turn session stalled after", 60, "min"),
            (VibraSettings.attentionDecay, "“Your turn” fades to idle after", 3600, "h"),
            (VibraSettings.activityWindow, "Show sessions active within", 3600, "h"),
        ]

        let grid = NSGridView(numberOfColumns: 4, rows: 0)
        grid.rowSpacing = 12
        grid.columnSpacing = 8
        for (limit, title, unit, unitName) in specs {
            let label = NSTextField(labelWithString: title)
            let field = NSTextField(string: "")
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 56).isActive = true
            field.target = self
            field.action = #selector(fieldChanged(_:))
            let stepper = NSStepper()
            stepper.minValue = limit.range.lowerBound / unit
            stepper.maxValue = limit.range.upperBound / unit
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.target = self
            stepper.action = #selector(stepperChanged(_:))
            let range = NSTextField(labelWithString:
                "\(unitName) (\(Int(stepper.minValue))–\(Int(stepper.maxValue)))")
            range.textColor = .secondaryLabelColor
            grid.addRow(with: [label, field, stepper, range])
            rows.append(Row(limit: limit, unit: unit, field: field, stepper: stepper))
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        // Keep rows at their natural height; without this the stack view
        // stretched the grid and gave the slack to one row.
        grid.setContentHuggingPriority(.required, for: .vertical)
        for i in 0..<grid.numberOfRows { grid.row(at: i).yPlacement = .center }

        let note = NSTextField(wrappingLabelWithString:
            "Saved as you change them and applied on the next refresh. Stored in "
            + "the ai.silexlab.vibra preferences — the only thing Vibra writes.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))

        let stack = NSStackView(views: [grid, note, reset])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        w.contentView = stack
        window = w
    }

    private func load() {
        let settings = VibraSettings.load(from: store)
        for row in rows {
            let seconds: TimeInterval
            switch row.limit.key {
            case VibraSettings.stallThreshold.key: seconds = settings.stallThresholdSeconds
            case VibraSettings.attentionDecay.key: seconds = settings.attentionDecaySeconds
            default: seconds = settings.activityWindowSeconds
            }
            row.stepper.doubleValue = (seconds / row.unit).rounded()
            row.field.stringValue = String(Int(row.stepper.doubleValue))
        }
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        guard let row = rows.first(where: { $0.stepper === sender }) else { return }
        save(row, units: sender.doubleValue)
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        guard let row = rows.first(where: { $0.field === sender }) else { return }
        save(row, units: Double(sender.stringValue.trimmingCharacters(in: .whitespaces)) ?? row.stepper.doubleValue)
    }

    private func save(_ row: Row, units: Double) {
        store.set(units * row.unit, forKey: row.limit.key)
        load()  // shows the clamped value if the input was out of range
        onChange?()
    }

    @objc private func restoreDefaults() {
        VibraSettings.reset(in: store)
        load()
        onChange?()
    }
}
