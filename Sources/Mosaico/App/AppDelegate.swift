import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboarding: PermissionsOnboarding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App solo-menubar anche se lanciata da `swift run` (senza Info.plist LSUIElement)
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
