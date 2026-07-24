import AppKit
import SwiftUI

/// Settings window managed directly: SwiftUI's `Settings` scene opens
/// only via SPI selectors (`showSettingsWindow:`) that are unreliable in
/// a menubar-only app.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Impostazioni Mosaico"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
