import AppKit
import ApplicationServices
import CAXShim

/// Modalità diagnostica: `Mosaico --diag` stampa stato permessi, display e
/// finestre rilevate con la loro disposition, senza toccare nulla.
enum Diagnostics {
    static func run() {
        print("=== MOSAICO DIAG ===")
        print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
        print("Spaces per display: \(SpaceTracker.activeSpacesByDisplay())")
        print("Schermi: \(NSScreen.screens.count)")
        for screen in NSScreen.screens {
            print("  display \(DisplayManager.displayID(of: screen)) ax=\(DisplayManager.axVisibleFrame(of: screen))")
        }

        for app in WindowDiscovery.tileableApps() {
            let ax = AXApplication(pid: app.processIdentifier)
            let ready = ax.isReady
            let windows = ax.windows()
            print("\napp \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] pid=\(app.processIdentifier) ready=\(ready) finestre=\(windows.count)")
            for w in windows {
                let disp = RulesEngine.disposition(for: w, bundleID: app.bundleIdentifier)
                print("  [\(w.id)] role=\(w.role ?? "nil") subrole=\(w.subrole ?? "nil") resizable=\(w.isResizable) frame=\(w.frame) → \(disp)")
            }
        }
        print("\n=== FINE DIAG ===")
    }
}
