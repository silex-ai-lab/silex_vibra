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
/// A boolean two threads can share.
///
/// `--test-notification` waits for callbacks that arrive on a background
/// dispatch queue. The closures that set this are `@Sendable` (see below), and
/// a `@Sendable` closure cannot capture a mutable local `var`, so the flag is a
/// reference type with its own lock instead.
final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func signal() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

if CommandLine.arguments.contains("--test-notification") {
    guard Bundle.main.bundleIdentifier != nil else {
        print("FAIL: no bundle identifier - run this from inside Vibra.app, not the bare binary")
        exit(1)
    }
    print("bundle: \(Bundle.main.bundleIdentifier ?? "?")")
    let center = UNUserNotificationCenter.current()
    let done = CompletionFlag()

    // Both handlers are explicitly `@Sendable`, and that is load-bearing.
    // `Package.swift` is swift-tools-version 6.0, so top-level code in main.swift
    // is `@MainActor`-isolated and a closure written here inherits that isolation.
    // UserNotifications invokes these on a background dispatch queue, so the Swift 6
    // runtime's executor check fired on closure entry and trapped
    // (`dispatch_assert_queue_fail`, SIGTRAP, exit 133) before the first print could
    // even flush. `@Sendable` opts them out of the inherited isolation. Verified on
    // macOS 15.7.3 / Swift 6.1.2; the previous form crashed 100% of the time there.
    center.requestAuthorization(options: [.alert, .sound]) { @Sendable granted, error in
        print("authorization granted: \(granted)")
        if let error { print("authorization error: \(error.localizedDescription)") }
        guard granted else {
            print("RESULT: not authorized. Check System Settings > Notifications > Vibra.")
            done.signal()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "vibra"
        content.body = "Test notification - delivery works on this machine."
        // A fixed identifier, for the same reason the real path uses the session
        // id: macOS replaces a delivered notification that reuses one. With a
        // UUID per run every `--test-notification` left another permanent entry
        // in Notification Center, and nothing ever removed them — running the
        // diagnostic a few times while debugging built its own little pile.
        let request = UNNotificationRequest(
            identifier: "vibra.test",
            content: content,
            trigger: nil
        )
        // `.current()` again rather than capturing the outer `center`:
        // UNUserNotificationCenter is not Sendable, and capturing it in a
        // `@Sendable` closure is a warning. It is the same shared instance.
        UNUserNotificationCenter.current().add(request) { @Sendable addError in
            if let addError {
                print("RESULT: delivery FAILED - \(addError.localizedDescription)")
            } else {
                print("RESULT: notification posted. Look for a banner now.")
                print("If no banner appears, macOS accepted it but suppressed display")
                print("(common for ad-hoc signed bundles, or Do Not Disturb).")
            }
            done.signal()
        }
    }
    // Spin briefly so the async callbacks can run before the process exits.
    // A RunLoop spin rather than a semaphore wait: the callback queue is not
    // documented, and blocking the main thread would deadlock if it ever arrived
    // there. The 10s deadline bounds the wait either way.
    let deadline = Date().addingTimeInterval(10)
    while !done.isSet && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    exit(0)
}

// `Vibra --herdr-jump <pid>` focuses the herdr pane running <pid> and the
// terminal window showing it, then reports what it focused. Lets the herdr half
// of jump-back be checked against any process, not only an agent session.
if let i = CommandLine.arguments.firstIndex(of: "--herdr-jump"),
   i + 1 < CommandLine.arguments.count,
   let pid = Int32(CommandLine.arguments[i + 1]) {
    if let app = TerminalJumper.focusHerdr(pid: pid) {
        print("OK: focused in \(app)")
        exit(0)
    }
    print("FAIL: \(pid) is not in a herdr pane, or no terminal shows that herdr session")
    exit(1)
}

// `Vibra --notifications` prints vibra's notification authorization and every
// notification of its own that macOS still reports as delivered - ids only,
// never bodies. Answers "why is Notification Center still full?" directly.
// Run it from the installed bundle, like --test-notification.
if CommandLine.arguments.contains("--notifications") {
    guard Bundle.main.bundleIdentifier != nil else {
        print("FAIL: no bundle identifier - run this from inside Vibra.app, not the bare binary")
        exit(1)
    }
    let done = CompletionFlag()
    UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
        print("authorization: \(settings.authorizationStatus.rawValue) (0 notDetermined, 1 denied, 2 authorized, 3 provisional)")
        print("alert style: \(settings.alertStyle.rawValue) (0 none, 1 banner, 2 alert)")
        UNUserNotificationCenter.current().getDeliveredNotifications { @Sendable delivered in
            print("delivered: \(delivered.count)")
            for n in delivered.sorted(by: { $0.date > $1.date }) {
                print("  \(n.date)  \(n.request.identifier)")
            }
            done.signal()
        }
    }
    let deadline = Date().addingTimeInterval(10)
    while !done.isSet && Date() < deadline {
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

// `Vibra --locate` resolves each live session to the process and terminal it
// is running in. Diagnostic for terminal jump-back (P1.1).
// `Vibra --jump <projectName>` attempts a terminal jump from the CLI, so the
// mechanism can be verified without clicking a menu.
if let i = CommandLine.arguments.firstIndex(of: "--jump"),
   i + 1 < CommandLine.arguments.count {
    let wanted = CommandLine.arguments[i + 1]
    let now = Date()
    let engine = StateEngine()
    var matched: Session?
    for adapter in AdapterRegistry.all() {
        for s in adapter.discoverSessionsSafely()
            where now.timeIntervalSince(s.lastActivity) <= 12 * 3600
            && s.projectName == wanted {
            var s2 = s
            s2.state = engine.classify(lastEvent: s.lastEvent, lastActivity: s.lastActivity, now: now)
            if matched == nil { matched = s2 }
        }
    }
    guard let session = matched else {
        print("no live session with project name \(wanted)")
        exit(2)
    }
    print("jumping to \(session.agent.displayName) \(session.projectName) ...")
    switch TerminalJumper.jump(to: session) {
    case .jumped(let app):            print("OK: focused in \(app)")
    case .notLocatable:               print("FAIL: no published session->process link, or process exited")
    case .noControllingTerminal:      print("FAIL: process has no controlling terminal")
    case .notPermitted(let app):
        print("FAIL: macOS refused the Apple Event - vibra has no Automation permission for \(app)")
        print("      System Settings > Privacy & Security > Automation > Vibra > enable \(app)")
    case .noTerminalOwnsTTY(let tty, let owner):
        switch owner {
        case .multiplexer(let name):
            print("FAIL: \(tty) belongs to \(name); its panes are invisible to the emulator")
        case .emulator(let name):
            print("FAIL: \(tty) traces back to \(name), but it reported no tab owning that tty")
        case .unknown:
            print("FAIL: no terminal owns \(tty), and its ancestry names none vibra can drive")
        }
    }
    exit(0)
}

// `Vibra --report` prints the rolling-window usage report.
if CommandLine.arguments.contains("--report") {
    let ingest = ReportIngest(adapters: AdapterRegistry.all())
    nonisolated(unsafe) var done = false
    Task.detached {
        let t0 = Date()
        let samples = await ingest.collectSamples()
        let bytes = await ingest.lastBytesRead
        let report = ReportBuilder().build(samplesByAgent: samples)

        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        func fmtTok(_ n: Int) -> String {
            n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6)
                           : (n >= 1000 ? "\(n / 1000)k" : "\(n)")
        }

        print("Usage — last \(report.windowDays) days (rolling), to \(df.string(from: report.generatedAt))")
        print("Estimated API-equivalent value. Not a bill. Computed locally; nothing left this machine.")
        print("")
        print("  BY DAY")
        if report.days.isEmpty { print("    (no dated usage in window)") }
        for d in report.days {
            let unp = d.unpricedTokens > 0 ? "  +\(fmtTok(d.unpricedTokens)) unpriced" : ""
            print(String(format: "    %-12s %8s tok   ~$%.2f%@",
                         (df.string(from: d.day) as NSString).utf8String!,
                         (fmtTok(d.usage.total) as NSString).utf8String!,
                         d.estimatedValue, unp))
        }
        print("")
        print("  BY AGENT")
        for a in report.agents {
            let unp = a.unpricedTokens > 0 ? "  +\(fmtTok(a.unpricedTokens)) unpriced" : ""
            print(String(format: "    %-14s %8s tok   ~$%.2f%@",
                         (a.agent.displayName as NSString).utf8String!,
                         (fmtTok(a.usage.total) as NSString).utf8String!,
                         a.estimatedValue, unp))
        }
        print("")
        print(String(format: "  TOTAL          %8s tok   ~$%.2f",
                     (fmtTok(report.total.total) as NSString).utf8String!, report.estimatedValue))
        if report.unpricedTokens > 0 {
            print("    \(fmtTok(report.unpricedTokens)) tokens had no published rate and are excluded from the estimate.")
        }
        if report.undated.total > 0 {
            print("    \(fmtTok(report.undated.total)) tokens could not be dated (source has no per-record timestamps).")
        }
        print("")
        print(String(format: "  read %.1f MB in %.2fs", Double(bytes) / 1_048_576, Date().timeIntervalSince(t0)))
        done = true
    }
    let deadline = Date().addingTimeInterval(120)
    while !done && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(done ? 0 : 1)
}

// `Vibra --agents` shows which agents were detected on this machine and why.
if CommandLine.arguments.contains("--agents") {
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
    print("Detected agents (by state on disk, not by binary on PATH):")
    for d in AdapterRegistry.detections() {
        let mark = d.isPresent ? "yes" : "no "
        let last = d.lastActivity.map { df.string(from: $0) } ?? "never"
        let active = d.isActive(within: 12 * 3600) ? "  [active]" : ""
        print(String(format: "  %-14@ present=%@  sources=%-4d  last=%@%@",
                     d.kind.displayName as NSString, mark as NSString,
                     d.sourceCount, last as NSString, active as NSString))
    }
    let polled = AdapterRegistry.detected().map(\.kind.displayName).joined(separator: ", ")
    print("\nPolled: \(polled.isEmpty ? "(none)" : polled)")
    exit(0)
}

if CommandLine.arguments.contains("--locate") {
    let locator = ProcessLocator()
    let engine = StateEngine()
    let now = Date()
    for adapter in AdapterRegistry.all() {
        for s in adapter.discoverSessionsSafely()
            .filter({ now.timeIntervalSince($0.lastActivity) <= 12 * 3600 }) {
            let found = locator.locate(sessionID: s.id, agent: s.agent)
            let state = engine.classify(lastEvent: s.lastEvent, lastActivity: s.lastActivity, now: now)
            if let found {
                print("\(s.agent.displayName) \(s.projectName) [\(state.rawValue)]")
                print("   pid=\(found.pid) tty=\(found.tty ?? "none") cwd=\(found.cwd ?? "?")")
                // Who holds the tty, from the process ancestry. This is the
                // question a failed jump turns on, so printing it here means it
                // can be answered without clicking anything.
                let owner: String
                switch ProcessInspector.ttyOwner(of: found.pid) {
                case .emulator(let name):    owner = "emulator \(name) - jumpable"
                case .multiplexer("herdr"):  owner = "multiplexer herdr - jumpable via herdr's CLI"
                case .multiplexer(let name): owner = "multiplexer \(name) - not jumpable"
                case .unknown:               owner = "unknown"
                }
                print("   tty owner: \(owner)")
            } else {
                print("\(s.agent.displayName) \(s.projectName) [\(state.rawValue)]")
                print("   not locatable (no published pid link, or process exited)")
            }
        }
    }
    exit(0)
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
            print("  - \(s.projectName) [\(s.state.rawValue)] ev=\(s.lastEvent.rawValue) \(s.usage.total) tok \(costText) model=\(s.model ?? "?")\(s.scheduledTask.map { " task=\($0)" } ?? "")")
        }
    }
    print("total sessions: \(total)")
    exit(total > 0 ? 0 : 2)
}

// `Vibra --show-report [--snapshot <path>]` launches the GUI, opens the usage
// report, optionally writes the window's own rendered pixels to a PNG, and
// reports what it rendered. Used to confirm the window actually draws.
if CommandLine.arguments.contains("--show-report") {
    let snapshotPath = CommandLine.arguments.firstIndex(of: "--snapshot").flatMap { i -> String? in
        i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
    }
    let app = NSApplication.shared
    let controller = ReportWindowController(adapters: AdapterRegistry.all())
    let delegate = ReportOnlyDelegate(controller: controller, snapshotPath: snapshotPath)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}

// LSUIElement in the bundle Info.plist keeps this out of the Dock and the app
// switcher; the status item is the app's entire presence.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
