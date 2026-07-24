import AppKit

/// Applies the frames computed by the BSPTree to the real windows.
enum LayoutEngine {

    /// Usable workspace rect: visibleFrame − padding.
    static func workspaceRect(for screen: NSScreen) -> CGRect {
        let padding = CGFloat(SettingsStore.shared.settings.padding)
        return DisplayManager.axVisibleFrame(of: screen).insetBy(dx: padding, dy: padding)
    }

    /// Default float frame: grid 4:4:1:1:2:2 (centered, half width/height).
    static func floatFrame(for screen: NSScreen) -> CGRect {
        let rect = workspaceRect(for: screen)
        return CGRect(x: rect.origin.x + rect.width / 4,
                      y: rect.origin.y + rect.height / 4,
                      width: rect.width / 2,
                      height: rect.height / 2)
    }

    /// Applies the workspace layout on the display. Temporarily disables
    /// AXEnhancedUserInterface for the apps involved (animation bug), then a
    /// delayed re-apply for the windows that did not comply.
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

        // Floats (dialogs, fixed-size windows) stay ABOVE the tiled ones —
        // otherwise they disappear behind the tiling that covers the whole
        // screen (i3-style behavior)
        for (_, managed) in workspace.windows where managed.isFloating {
            managed.window.raise()
        }

        // Re-apply for apps slow to apply the frame (only once, 0.1s later).
        // Does NOT adopt the real frame: if the app snaps to a different
        // size (terminals on a cell grid), it is tolerated — chasing it
        // would create an apply→snap→adopt loop. Resize adoption happens
        // only on user action (handleDragEnd).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard workspace.layoutGeneration == generation,
                  NSEvent.pressedMouseButtons == 0 else { return }
            for (_, entries) in byPid {
                for (managed, target) in entries where !rectsEqual(managed.window.frame, target) {
                    managed.window.setFrame(target)
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
