import AppKit

/// A window the `--show-* --snapshot` diagnostics can open, wait for, and
/// render to a PNG without a Screen Recording grant.
@MainActor
protocol RenderableWindow: AnyObject {
    var onRendered: (() -> Void)? { get set }
    var renderedText: String { get }
    var windowIsVisible: Bool { get }
    var windowFrame: NSRect { get }
    func show()
    @discardableResult func snapshot(to url: URL) -> Bool
}

/// Draws a window's own content into a bitmap — the app rendering itself, so
/// no Screen Recording permission is involved.
@MainActor
func snapshotContent(of window: NSWindow?, to url: URL) -> Bool {
    guard let view = window?.contentView,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return false }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: url)) != nil
}
