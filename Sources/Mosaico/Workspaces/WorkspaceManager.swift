import AppKit

/// Un workspace (albero di tiling) per ogni (display, space nativo macOS).
///
/// Gli "spazi" sono SOLO quelli nativi di Mission Control: ogni space ha il
/// suo albero, le finestre di uno space non toccano mai il layout degli
/// altri, e il layout viene applicato solo allo space visibile.
final class WorkspaceManager {

    /// Stato di un singolo space nativo: un workspace.
    final class SpaceState {
        let workspace = Workspace()
    }

    /// Stato per display: uno SpaceState per ogni space nativo visto.
    final class DisplayState {
        let displayID: CGDirectDisplayID
        var spaces: [NativeSpaceID: SpaceState] = [:]

        init(displayID: CGDirectDisplayID) {
            self.displayID = displayID
        }
    }

    private(set) var displays: [CGDirectDisplayID: DisplayState] = [:]

    /// Posizione di una finestra nel modello.
    struct Location {
        let display: DisplayState
        let space: SpaceState
        let workspace: Workspace
        let managed: ManagedWindow
    }

    // MARK: - Setup display

    func syncDisplays() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = DisplayManager.displayID(of: screen)
            seen.insert(id)
            if displays[id] == nil {
                displays[id] = DisplayState(displayID: id)
            }
        }
        // Display scollegati: merge delle finestre sul primario
        let orphans = displays.keys.filter { !seen.contains($0) }
        guard let primary = NSScreen.screens.first else { return }
        for orphanID in orphans {
            guard let orphan = displays.removeValue(forKey: orphanID) else { continue }
            let target = activeWorkspace(for: primary)
            for (_, spaceState) in orphan.spaces {
                for (_, managed) in spaceState.workspace.windows {
                    target.add(managed, near: nil, leafRect: { _ in managed.window.frame })
                }
            }
        }
    }

    // MARK: - Risoluzione space/workspace

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

    /// Workspace dello space nativo attualmente visibile sul display.
    func activeWorkspace(for screen: NSScreen) -> Workspace {
        let spaceID = SpaceTracker.currentSpace(for: screen) ?? 0
        return spaceState(displayID: DisplayManager.displayID(of: screen), spaceID: spaceID).workspace
    }

    /// True se il workspace appartiene allo space VISIBILE del suo display.
    func isVisible(_ workspace: Workspace) -> Bool {
        for (displayID, display) in displays {
            for (spaceID, spaceState) in display.spaces where spaceState.workspace === workspace {
                guard let screen = DisplayManager.screen(withDisplayID: displayID) else { return false }
                return SpaceTracker.currentSpace(for: screen) == spaceID
            }
        }
        return false
    }

    /// Cerca la finestra in tutto il modello.
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
