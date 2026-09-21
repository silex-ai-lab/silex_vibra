import AppKit
import VibraCore

/// Launches straight into the usage report, reports what rendered, and exits.
/// Exists so the window can be verified without a human clicking a menu and
/// without Screen Recording permission.
@MainActor
final class ReportOnlyDelegate: NSObject, NSApplicationDelegate {
    private let controller: ReportWindowController
    private let snapshotPath: String?

    init(controller: ReportWindowController, snapshotPath: String?) {
        self.controller = controller
        self.snapshotPath = snapshotPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.onRendered = { [weak self] in
            guard let self else { return }
            // One runloop turn so AppKit has actually drawn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let text = self.controller.renderedText
                print("window visible : \(self.controller.windowIsVisible)")
                let f = self.controller.windowFrame
                print("window frame   : \(Int(f.width))x\(Int(f.height))")
                print("rendered chars : \(text.count)")
                print("rendered lines : \(text.split(separator: "\n").count)")
                if let path = self.snapshotPath {
                    let ok = self.controller.snapshot(to: URL(fileURLWithPath: path))
                    print("snapshot       : \(ok ? "written to \(path)" : "FAILED")")
                }
                print("--- first lines ---")
                for line in text.split(separator: "\n").prefix(6) { print(line) }
                NSApp.terminate(nil)
            }
        }
        controller.show()
    }
}
