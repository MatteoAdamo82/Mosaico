import AppKit
import SwiftUI

/// Finestra Impostazioni gestita direttamente: la scene `Settings` di SwiftUI
/// si apre solo tramite selettori SPI (`showSettingsWindow:`) inaffidabili in
/// un'app solo-menubar.
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
