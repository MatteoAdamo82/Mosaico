import AppKit

/// Overlay traslucido che evidenzia la zona di drop durante il drag
/// (swap = tutta la finestra target, warp = la metà interessata).
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

    /// Mostra (o sposta) l'overlay sul rect in coordinate AX.
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
