import AppKit
import VibraCore

// LSUIElement is set in the bundle Info.plist, so there is no dock icon and no
// menu bar of our own - the status item is the entire presence of this app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
