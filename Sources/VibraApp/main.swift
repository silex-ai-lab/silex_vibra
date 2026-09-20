import AppKit
import UserNotifications
import VibraCore

// `VibraApp --probe` runs every adapter once, prints a summary, and exits.
// Diagnostics only: counts, project names and states - never message content.
// `Vibra --test-notification` posts one notification and reports what macOS
// said about it. Run it from the INSTALLED bundle, not a bare binary:
//   /Applications/Vibra.app/Contents/MacOS/Vibra --test-notification
// Notification delivery is not guaranteed for an ad-hoc signed bundle, so this
// exists to answer "does it work on this machine?" without guessing.
if CommandLine.arguments.contains("--test-notification") {
    guard Bundle.main.bundleIdentifier != nil else {
        print("FAIL: no bundle identifier - run this from inside Vibra.app, not the bare binary")
        exit(1)
    }
    print("bundle: \(Bundle.main.bundleIdentifier ?? "?")")
    let center = UNUserNotificationCenter.current()
    var done = false
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        print("authorization granted: \(granted)")
        if let error { print("authorization error: \(error.localizedDescription)") }
        guard granted else {
            print("RESULT: not authorized. Check System Settings > Notifications > Vibra.")
            done = true
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "vibra"
        content.body = "Test notification - delivery works on this machine."
        let request = UNNotificationRequest(
            identifier: "vibra.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { addError in
            if let addError {
                print("RESULT: delivery FAILED - \(addError.localizedDescription)")
            } else {
                print("RESULT: notification posted. Look for a banner now.")
                print("If no banner appears, macOS accepted it but suppressed display")
                print("(common for ad-hoc signed bundles, or Do Not Disturb).")
            }
            done = true
        }
    }
    // Spin briefly so the async callbacks can run before the process exits.
    let deadline = Date().addingTimeInterval(10)
    while !done && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    exit(0)
}

// `Vibra --bench` measures the Phase 0 acceptance criteria directly: how long
// a cold pass takes, and how many bytes a warm pass reads when nothing has
// changed. The warm number must be 0.
if CommandLine.arguments.contains("--bench") {
    let ingest = SessionIngest(adapters: AdapterRegistry.all())
    // Top-level code in main.swift is MainActor-isolated under Swift 6, so a
    // plain Task{} here inherits the main actor and blocking on a semaphore
    // deadlocks against the very actor the work needs. Detach, and spin the
    // runloop instead of blocking it.
    nonisolated(unsafe) var finished = false
    Task.detached {
        var t0 = Date()
        let cold = await ingest.refresh()
        let coldSeconds = Date().timeIntervalSince(t0)
        let coldBytes = await ingest.lastRefreshBytesRead

        t0 = Date()
        _ = await ingest.refresh()
        let warmSeconds = Date().timeIntervalSince(t0)
        let warmBytes = await ingest.lastRefreshBytesRead

        t0 = Date()
        for _ in 0..<10 { _ = await ingest.refresh() }
        let tenWarm = Date().timeIntervalSince(t0)

        print(String(format: "cold refresh : %6.2fs  %10d bytes  %d sessions",
                     coldSeconds, coldBytes, cold.count))
        print(String(format: "warm refresh : %6.2fs  %10d bytes", warmSeconds, warmBytes))
        print(String(format: "10x warm     : %6.2fs  (%.1f ms each)",
                     tenWarm, tenWarm * 100))
        print(warmBytes == 0
              ? "PASS: an unchanged refresh reads zero bytes"
              : "FAIL: an unchanged refresh still read \(warmBytes) bytes")
        finished = true
    }
    let deadline = Date().addingTimeInterval(300)
    while !finished && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(finished ? 0 : 1)
}

if CommandLine.arguments.contains("--probe") {
    var total = 0
    let aggregator = UsageAggregator()
    let engine = StateEngine()
    let now = Date()
    let window: TimeInterval = 12 * 3600
    for adapter in AdapterRegistry.all() {
        let sessions = adapter.discoverSessionsSafely()
            .filter { now.timeIntervalSince($0.lastActivity) <= window }
            .map { s -> Session in
                var s = s
                s.state = engine.classify(lastEvent: s.lastEvent, lastActivity: s.lastActivity, now: now)
                return s
            }
            .sorted { $0.lastActivity > $1.lastActivity }
        total += sessions.count
        print("\(adapter.kind.displayName): available=\(adapter.isAvailable) sessions=\(sessions.count)")
        for s in sessions.prefix(5) {
            let cost = aggregator.cost(for: s)
            let costText = cost.map { String(format: "$%.4f", $0) } ?? "n/a"
            print("  - \(s.projectName) [\(s.state.rawValue)] ev=\(s.lastEvent.rawValue) \(s.usage.total) tok \(costText) model=\(s.model ?? "?")")
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
