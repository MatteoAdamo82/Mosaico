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
        // Confronto: cosa vede il window server (tutti gli spaces)
        print("\n--- CGWindowList (tutte le finestre layer 0, tutti gli spaces) ---")
        let options: CGWindowListOption = [.excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let number = info[kCGWindowNumber as String] as? UInt32,
                      let owner = info[kCGWindowOwnerName as String] as? String else { continue }
                let title = info[kCGWindowName as String] as? String ?? "?"
                let space = SpaceTracker.space(of: number).map(String.init) ?? "?"
                let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) == true
                print("  [\(number)] \(owner) '\(title)' space=\(space) onscreen=\(onScreen)")
            }
        }
        print("\n=== FINE DIAG ===")
    }
}
