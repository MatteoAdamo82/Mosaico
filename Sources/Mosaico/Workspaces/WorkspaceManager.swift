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

    /// Stato dei display temporaneamente assenti (es. durante lo standby):
    /// conservato per non distruggere il layout se il display ritorna.
    private var detachedDisplays: [CGDirectDisplayID: DisplayState] = [:]

    func syncDisplays() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = DisplayManager.displayID(of: screen)
            seen.insert(id)
            if displays[id] == nil {
                // Display ricomparso (wake): ripristina lo stato conservato
                displays[id] = detachedDisplays.removeValue(forKey: id) ?? DisplayState(displayID: id)
            }
        }
        // Display spariti: NON fondere subito — al wake riappaiono in pochi
        // secondi. Sposta lo stato in "detached"; il merge sul primario
        // avviene solo se il display resta assente (vedi mergeStaleDetached).
        let orphans = displays.keys.filter { !seen.contains($0) }
        for orphanID in orphans {
            if let orphan = displays.removeValue(forKey: orphanID) {
                detachedDisplays[orphanID] = orphan
            }
        }
    }

    /// Fonde sul primario le finestre dei display rimasti assenti a lungo
    /// (unplug reale, non standby). Da chiamare dopo un grace period.
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
