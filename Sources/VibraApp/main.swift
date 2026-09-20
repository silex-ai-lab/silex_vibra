import AppKit
import VibraCore

// `VibraApp --probe` runs every adapter once, prints a summary, and exits.
// Diagnostics only: counts, project names and states - never message content.
if CommandLine.arguments.contains("--probe") {
    var total = 0
    let aggregator = UsageAggregator()
    for adapter in AdapterRegistry.all() {
        let sessions = adapter.discoverSessionsSafely()
        total += sessions.count
        print("\(adapter.kind.displayName): available=\(adapter.isAvailable) sessions=\(sessions.count)")
        for s in sessions.prefix(5) {
            let cost = aggregator.cost(for: s)
            let costText = cost.map { String(format: "$%.4f", $0) } ?? "n/a"
            print("  - \(s.projectName) [\(s.state.rawValue)] \(s.usage.total) tok \(costText) model=\(s.model ?? "?")")
        }
    }
    print("total sessions: \(total)")
    exit(total > 0 ? 0 : 2)
}

// LSUIElement in the bundle Info.plist keeps this out of the Dock and the app
// switcher; the status item is the app's entire presence.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
