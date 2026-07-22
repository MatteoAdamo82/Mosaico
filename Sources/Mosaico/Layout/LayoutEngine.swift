import AppKit

/// Applica i frame calcolati dal BSPTree alle finestre reali.
enum LayoutEngine {

    /// Rect utile del workspace: visibleFrame − padding.
    static func workspaceRect(for screen: NSScreen) -> CGRect {
        let padding = CGFloat(SettingsStore.shared.settings.padding)
        return DisplayManager.axVisibleFrame(of: screen).insetBy(dx: padding, dy: padding)
    }

    /// Frame float di default: grid 4:4:1:1:2:2 (centrata, metà larghezza/altezza).
    static func floatFrame(for screen: NSScreen) -> CGRect {
        let rect = workspaceRect(for: screen)
        return CGRect(x: rect.origin.x + rect.width / 4,
                      y: rect.origin.y + rect.height / 4,
                      width: rect.width / 2,
                      height: rect.height / 2)
    }

    /// Applica il layout del workspace sul display. Disattiva temporaneamente
    /// AXEnhancedUserInterface per app coinvolte (bug animazioni), poi un
    /// re-apply ritardato per le finestre che non hanno obbedito.
    static func apply(workspace: Workspace, on screen: NSScreen) {
        let rect = workspaceRect(for: screen)
        let gap = CGFloat(SettingsStore.shared.settings.gap)
        let frames = workspace.tree.frames(in: rect, gap: gap)

        workspace.layoutGeneration += 1
        let generation = workspace.layoutGeneration

        var byPid: [pid_t: [(ManagedWindow, CGRect)]] = [:]
        for (id, frame) in frames {
            guard let managed = workspace.windows[id], !managed.isFloating else { continue }
            let target = managed.isZoomed ? rect : frame
            byPid[managed.window.pid, default: []].append((managed, target))
        }

        var changed = 0
        for (pid, entries) in byPid {
            let app = AXApplication(pid: pid)
            let hadEnhanced = app.enhancedUserInterface
            if hadEnhanced { app.enhancedUserInterface = false }

            for (managed, target) in entries {
                if !rectsEqual(managed.window.frame, target) {
                    managed.window.setFrame(target)
                    changed += 1
                }
            }

            if hadEnhanced { app.enhancedUserInterface = true }
        }
        if changed > 0 {
            MosaicoLog.log("apply gen=\(generation) set=\(changed)")
        }

        // Re-apply per i ritardatari; le "stubborn" adottano il frame reale nel ratio.
        // Salta se nel frattempo il layout è cambiato (frame ormai stali) o se
        // c'è un drag in corso.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard workspace.layoutGeneration == generation,
                  NSEvent.pressedMouseButtons == 0 else { return }
            for (_, entries) in byPid {
                for (managed, target) in entries {
                    let actual = managed.window.frame
                    if !rectsEqual(actual, target) {
                        managed.window.setFrame(target)
                        let after = managed.window.frame
                        // Adotta solo scostamenti significativi: sotto i 6pt è
                        // snapping dell'app, inseguirlo crea oscillazioni
                        if !rectsEqual(after, target, tolerance: 6) {
                            workspace.tree.adoptFrame(for: managed.id, actual: after, in: rect, gap: gap)
                        }
                    }
                }
            }
        }
    }

    static func rectsEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.width - b.width) <= tolerance &&
        abs(a.height - b.height) <= tolerance
    }
}
