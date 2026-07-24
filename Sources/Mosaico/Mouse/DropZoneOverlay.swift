import AppKit

/// Translucent overlay that highlights the drop zone during the drag
/// (swap = the whole target window, warp = the affected half).
final class DropZoneOverlay {
    static let shared = DropZoneOverlay()

    private var window: NSWindow?

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 8
        window.contentView = view
        return window
    }

    /// Shows (or moves) the overlay to the rect in AX coordinates.
    func show(axRect: CGRect) {
        let cocoa = DisplayManager.cocoaRect(fromAX: axRect)
        if window == nil { window = makeWindow() }
        window?.setFrame(cocoa, display: true)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}
