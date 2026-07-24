import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboarding: PermissionsOnboarding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only app even when launched via `swift run` (without Info.plist LSUIElement)
        NSApp.setActivationPolicy(.accessory)

        MosaicoLog.rotate()
        MosaicoLog.log("avvio: AXIsProcessTrusted=\(AXIsProcessTrusted())")

        if AXIsProcessTrusted() {
            WindowManager.shared.start()
        } else {
            let onboarding = PermissionsOnboarding {
                WindowManager.shared.start()
            }
            self.onboarding = onboarding
            onboarding.begin()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.stop()
    }
}
