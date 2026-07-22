import AppKit
import SwiftUI

/// Mostra la finestra di onboarding finché il permesso Accessibility non viene
/// concesso, poi chiama `onGranted` (senza bisogno di riavviare l'app).
final class PermissionsOnboarding {
    private let onGranted: () -> Void
    private var window: NSWindow?
    private var timer: Timer?

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
    }

    func begin() {
        // Prompt di sistema (una volta sola)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        showWindow()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.window?.close()
            self.window = nil
            self.onGranted()
        }
    }

    private func showWindow() {
        let view = OnboardingView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Benvenuto in Mosaico"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Mosaico organizza le tue finestre")
                .font(.title2.bold())

            Text("Per gestire le finestre delle altre app, macOS richiede il permesso **Accessibilità**.\n\nApri Impostazioni di Sistema → Privacy e Sicurezza → Accessibilità e attiva Mosaico. Questa finestra si chiuderà da sola appena il permesso è attivo.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button("Apri Impostazioni di Sistema") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }
}
