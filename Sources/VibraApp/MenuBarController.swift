import AppKit
import VibraCore

/// Owns the status item. Placeholder wiring; real rendering lands in task 8.
final class MenuBarController {
    private var statusItem: NSStatusItem?

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "vibra"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit vibra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
