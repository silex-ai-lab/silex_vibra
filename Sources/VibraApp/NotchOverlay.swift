import AppKit
import VibraCore

/// A borderless panel pinned under the camera housing on notched Macs.
///
/// This is progressive enhancement, not the product. `makeIfSupported` returns
/// nil on any display without a notch, and every call site must tolerate that:
/// the menu bar is the complete experience on its own.
@MainActor
final class NotchOverlay {
    private let panel: NSPanel
    private let label: NSTextField

    /// Returns an overlay only when the main screen actually has a notch.
    ///
    /// `auxiliaryTopLeftArea` is non-nil exactly when there is a camera housing
    /// with usable menu-bar area beside it. On a Mac mini or any external
    /// display this is nil and we build nothing at all.
    static func makeIfSupported(screen: NSScreen? = NSScreen.main) -> NotchOverlay? {
        guard let screen, screen.auxiliaryTopLeftArea != nil else { return nil }
        return NotchOverlay(screen: screen)
    }

    private init(screen: NSScreen) {
        let width: CGFloat = 220
        let height: CGFloat = 30
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Visible over full-screen apps, and not captured in screen sharing.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 6, width: width, height: 18)

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.addSubview(label)
        panel.contentView = content
    }

    func update(sessions: [Session]) {
        let attention = sessions.filter { $0.state.needsAttention }
        if let first = attention.first {
            label.stringValue = "● \(first.projectName) needs you"
            panel.orderFrontRegardless()
        } else if sessions.contains(where: { $0.state == .working }) {
            let n = sessions.filter { $0.state == .working }.count
            label.stringValue = "◐ \(n) working"
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }
}
