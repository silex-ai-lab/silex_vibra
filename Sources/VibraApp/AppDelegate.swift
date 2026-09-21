import AppKit
import VibraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var store: SessionStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SessionStore(adapters: AdapterRegistry.detected())
        let menuBar = MenuBarController(store: store)
        menuBar.start()
        self.store = store
        self.menuBar = menuBar
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.shutdown()
        store?.stop()
    }
}
