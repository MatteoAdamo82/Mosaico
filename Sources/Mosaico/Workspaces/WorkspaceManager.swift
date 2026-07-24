import AppKit

/// One workspace (tiling tree) for each (display, native macOS space).
///
/// The "spaces" are ONLY the native Mission Control ones: each space has its
/// own tree, the windows of one space never touch the layout of the others,
/// and the layout is applied only to the visible space.
final class WorkspaceManager {

    /// State of a single native space: a workspace.
    final class SpaceState {
        let workspace = Workspace()
    }

    /// Per-display state: one SpaceState for each native space seen.
    final class DisplayState {
        let displayID: CGDirectDisplayID
        var spaces: [NativeSpaceID: SpaceState] = [:]

        init(displayID: CGDirectDisplayID) {
            self.displayID = displayID
        }
    }

    private(set) var displays: [CGDirectDisplayID: DisplayState] = [:]

    /// Position of a window in the model.
    struct Location {
        let display: DisplayState
        let space: SpaceState
        let workspace: Workspace
        let managed: ManagedWindow
    }

    // MARK: - Display setup

    /// State of temporarily absent displays (e.g. during standby):
    /// kept so the layout is not destroyed if the display returns.
    private var detachedDisplays: [CGDirectDisplayID: DisplayState] = [:]

    func syncDisplays() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = DisplayManager.displayID(of: screen)
            seen.insert(id)
            if displays[id] == nil {
                // Display reappeared (wake): restore the kept state
                displays[id] = detachedDisplays.removeValue(forKey: id) ?? DisplayState(displayID: id)
            }
        }
        // Vanished displays: do NOT merge immediately — on wake they reappear
        // within a few seconds. Move the state to "detached"; the merge onto
        // the primary happens only if the display stays absent (see mergeStaleDetached).
        let orphans = displays.keys.filter { !seen.contains($0) }
        for orphanID in orphans {
            if let orphan = displays.removeValue(forKey: orphanID) {
                detachedDisplays[orphanID] = orphan
            }
        }
    }

    /// Merges onto the primary the windows of displays that stayed absent for
    /// a long time (real unplug, not standby). To be called after a grace period.
    func mergeStaleDetached() {
        guard !detachedDisplays.isEmpty,
              let primary = NSScreen.screens.first else { return }
        let target = activeWorkspace(for: primary)
        for (_, orphan) in detachedDisplays {
            for (_, spaceState) in orphan.spaces {
                for (_, managed) in spaceState.workspace.windows {
                    target.add(managed, near: nil, leafRect: { _ in managed.window.frame })
                }
            }
        }
        detachedDisplays.removeAll()
    }

    // MARK: - Space/workspace resolution

    private func displayState(for id: CGDirectDisplayID) -> DisplayState {
        if let state = displays[id] { return state }
        let state = DisplayState(displayID: id)
        displays[id] = state
        return state
    }

    func spaceState(displayID: CGDirectDisplayID, spaceID: NativeSpaceID) -> SpaceState {
        let display = displayState(for: displayID)
        if let state = display.spaces[spaceID] { return state }
        let state = SpaceState()
        display.spaces[spaceID] = state
        return state
    }

    /// Workspace of the native space currently visible on the display.
    func activeWorkspace(for screen: NSScreen) -> Workspace {
        let spaceID = SpaceTracker.currentSpace(for: screen) ?? 0
        return spaceState(displayID: DisplayManager.displayID(of: screen), spaceID: spaceID).workspace
    }

    /// True if the workspace belongs to the VISIBLE space of its display.
    func isVisible(_ workspace: Workspace) -> Bool {
        for (displayID, display) in displays {
            for (spaceID, spaceState) in display.spaces where spaceState.workspace === workspace {
                guard let screen = DisplayManager.screen(withDisplayID: displayID) else { return false }
                return SpaceTracker.currentSpace(for: screen) == spaceID
            }
        }
        return false
    }

    /// Searches for the window across the whole model.
    func locate(_ id: WindowID) -> Location? {
        for (_, display) in displays {
            for (_, spaceState) in display.spaces {
                if let managed = spaceState.workspace.windows[id] {
                    return Location(display: display, space: spaceState,
                                    workspace: spaceState.workspace, managed: managed)
                }
            }
        }
        return nil
    }
}
