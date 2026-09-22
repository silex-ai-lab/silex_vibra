import AppKit
import VibraCore

/// A small panel showing the rolling usage report.
///
/// Built on demand: the seven-day read costs seconds and hundreds of
/// megabytes, which is fine for an explicit action and would be ruinous on the
/// polling path. The window shows a loading line first rather than blocking
/// the menu.
@MainActor
final class ReportWindowController {
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
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
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
        Task { [weak self] in
            let started = Date()
            let samples = await ingest.collectSamples()
            let bytes = await ingest.lastBytesRead
            let report = ReportBuilder().build(samplesByAgent: samples)
            await MainActor.run {
                self?.isLoading = false
                self?.render(Self.format(report, bytes: bytes, seconds: Date().timeIntervalSince(started)))
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

    /// Wording is deliberate. The figure is an estimate of what this usage
    /// would have cost at published API rates — on a subscription you pay a
    /// flat fee — so it is never called a cost, a bill, or a quota. Unpriced
    /// and undated tokens get their own lines rather than vanishing into a
    /// total that would then look authoritative and be wrong.
    static func format(_ r: UsageReport, bytes: Int, seconds: TimeInterval) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        func tok(_ n: Int) -> String {
            n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6)
                           : (n >= 1_000 ? "\(n / 1_000)k" : "\(n)")
        }
        // String(format:) ignores width specifiers for %@, so columns are
        // padded by hand. Without this the figures come out ragged and the
        // table is much harder to scan than a table should be.
        func padRight(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }
        func padLeft(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
        }
        func row(_ label: String, _ usage: TokenUsage, _ value: Double, _ unpriced: Int) -> String {
            var line = "  " + padRight(label, 16)
                + padLeft(tok(usage.total), 8) + " tok"
                + padLeft(String(format: "~$%.2f", value), 12)
            if unpriced > 0 { line += "   +\(tok(unpriced)) unpriced" }
            return line + "\n"
        }

        var out = "USAGE — last \(r.windowDays) days (rolling)\n"
        out += "\(df.string(from: r.windowStart)) – \(df.string(from: r.generatedAt))\n\n"

        out += "BY DAY\n"
        if r.days.isEmpty { out += "  (no dated usage in this window)\n" }
        for d in r.days {
            out += row(df.string(from: d.day), d.usage, d.estimatedValue, d.unpricedTokens)
        }

        out += "\nBY AGENT\n"
        for a in r.agents {
            out += row(a.agent.displayName, a.usage, a.estimatedValue, a.unpricedTokens)
        }

        out += "\n" + "  " + padRight("TOTAL", 16)
            + padLeft(tok(r.total.total), 8) + " tok"
            + padLeft(String(format: "~$%.2f", r.estimatedValue), 12) + "\n"

        if r.unpricedTokens > 0 {
            out += "  \(tok(r.unpricedTokens)) tokens have no published rate and\n"
            out += "  are excluded from the estimate above.\n"
        }
        if r.undated.total > 0 {
            out += "  \(tok(r.undated.total)) tokens could not be dated: that source\n"
            out += "  records per-session totals with no timestamps.\n"
        }

        out += "\n———\n"
        out += "Estimated API-equivalent value, not a bill. On a\n"
        out += "subscription you pay a flat fee; this is what the same\n"
        out += "usage would cost at published API rates.\n"
        out += "Computed locally. Nothing left this machine.\n"
        out += String(format: "\nRead %.1f MB in %.1fs.\n", Double(bytes) / 1_048_576, seconds)
        return out
    }
}
