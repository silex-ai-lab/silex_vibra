import AppKit
import VibraCore

/// A small panel showing the rolling usage report.
///
/// Built on demand: the seven-day read costs seconds and hundreds of
/// megabytes, which is fine for an explicit action and would be ruinous on the
/// polling path. The window shows a loading line first rather than blocking
/// the menu.
@MainActor
final class ReportWindowController: RenderableWindow {
    private var window: NSWindow?
    private var textView: NSTextView?
    private let adapters: [any AgentAdapter]
    private var isLoading = false

    init(adapters: [any AgentAdapter]) {
        self.adapters = adapters
    }

    /// Called once the report has finished loading and rendering.
    var onRendered: (() -> Void)?

    /// Writes the window's own rendered content to a PNG.
    ///
    /// Draws the view into a bitmap rather than capturing the screen, so it
    /// needs no Screen Recording grant — the app is only rendering itself.
    @discardableResult
    func snapshot(to url: URL) -> Bool {
        snapshotContent(of: window, to: url)
    }

    /// Rendered text, for verifying content without an image.
    var renderedText: String { textView?.string ?? "" }

    var windowIsVisible: Bool { window?.isVisible ?? false }
    var windowFrame: NSRect { window?.frame ?? .zero }

    func show() {
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard !isLoading else { return }
        isLoading = true
        render("Reading the last 7 days…")

        let ingest = ReportIngest(adapters: adapters)
        let thresholds = PerfThresholds.load(from: PreferencesStore())
        Task { [weak self] in
            let started = Date()
            let window = ReportWindow(now: started, days: 7, calendar: .current)
            let input = await ingest.collect(window: window)
            let report = ReportBuilder().build(samplesByAgent: input.samplesByAgent, window: window)
            let perf = PerfAnalyzer.report(
                claudeSources: input.sources[.claudeCode] ?? [], window: window, thresholds: thresholds)
            await MainActor.run {
                self?.isLoading = false
                self?.render(ReportText.render(usage: report, perf: perf, read: input.read,
                                               seconds: Date().timeIntervalSince(started)))
                // Let the text view lay out before anyone snapshots it.
                self?.textView?.layoutManager?.ensureLayout(for: self!.textView!.textContainer!)
                self?.onRendered?()
            }
        }
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Vibra — usage"
        w.isReleasedWhenClosed = false
        w.center()

        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = NSSize(width: 16, height: 14)
        text.autoresizingMask = [.width]

        scroll.documentView = text
        w.contentView = scroll
        window = w
        textView = text
    }

    private func render(_ body: String) {
        textView?.string = body
    }
}
