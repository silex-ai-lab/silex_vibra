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
            }
        }
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "vibra — usage"
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

        var out = "USAGE — last \(r.windowDays) days (rolling)\n"
        out += "\(df.string(from: r.windowStart)) – \(df.string(from: r.generatedAt))\n\n"

        out += "BY DAY\n"
        if r.days.isEmpty {
            out += "  (no dated usage in this window)\n"
        }
        for d in r.days {
            out += String(format: "  %-12@ %9@ tok   ~$%.2f%@\n",
                          df.string(from: d.day) as NSString,
                          tok(d.usage.total) as NSString,
                          d.estimatedValue,
                          (d.unpricedTokens > 0 ? "  +\(tok(d.unpricedTokens)) unpriced" : "") as NSString)
        }

        out += "\nBY AGENT\n"
        for a in r.agents {
            out += String(format: "  %-14@ %9@ tok   ~$%.2f%@\n",
                          a.agent.displayName as NSString,
                          tok(a.usage.total) as NSString,
                          a.estimatedValue,
                          (a.unpricedTokens > 0 ? "  +\(tok(a.unpricedTokens)) unpriced" : "") as NSString)
        }

        out += String(format: "\nTOTAL           %9@ tok   ~$%.2f\n",
                      tok(r.total.total) as NSString, r.estimatedValue)

        if r.unpricedTokens > 0 {
            out += "  \(tok(r.unpricedTokens)) tokens have no published rate and are excluded above.\n"
        }
        if r.undated.total > 0 {
            out += "  \(tok(r.undated.total)) tokens could not be dated — that source records\n"
            out += "  per-session totals with no per-record timestamps.\n"
        }

        out += "\n—\n"
        out += "Estimated API-equivalent value, not a bill. On a subscription you pay a\n"
        out += "flat fee; this is what the same usage would cost at published API rates.\n"
        out += "Computed locally from token counts. Nothing left this machine.\n"
        out += String(format: "\nRead %.1f MB in %.1fs.\n", Double(bytes) / 1_048_576, seconds)
        return out
    }
}
