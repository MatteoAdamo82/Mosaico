import AppKit

/// One workspace (tiling tree) for each native macOS space.
///
/// Spaces are the unit, not displays. When a monitor is plugged or
/// unplugged macOS moves whole spaces between displays — the windows stay
/// on their space — and display IDs are not stable across reconnections.
/// A tree keyed by its space simply follows the space wherever it is
/// shown: nothing has to be detached, merged or restored when the display
/// set changes, and the layout is applied only to the spaces on screen.
///
/// A key is pinned to a display only when the space cannot be told apart
/// by its ID: the ID is unknown (CGS unavailable) or the same space is
/// shown on every display ("Displays have separate Spaces" turned off).
final class WorkspaceManager {

    struct SpaceKey: Hashable {
        let space: NativeSpaceID
        let pinnedDisplay: CGDirectDisplayID?
    }

    final class SpaceState {
        let workspace = Workspace()
    }

    private(set) var spaces: [SpaceKey: SpaceState] = [:]

    /// Position of a window in the model.
    struct Location {
        let key: SpaceKey
        let workspace: Workspace
        let managed: ManagedWindow
    }

    // MARK: - Key resolution

    /// Key of the space currently visible on the display.
    func key(for screen: NSScreen) -> SpaceKey {
        let byDisplay = SpaceTracker.activeSpacesByDisplay()
        let space = SpaceTracker.currentSpace(for: screen, in: byDisplay)
        return key(space: space, on: screen, byDisplay: byDisplay)
    }

    /// Key for a window known to be on `space`, shown on `screen`.
    func key(space: NativeSpaceID?, on screen: NSScreen) -> SpaceKey {
        key(space: space, on: screen, byDisplay: SpaceTracker.activeSpacesByDisplay())
    }

    private func key(space: NativeSpaceID?, on screen: NSScreen,
                     byDisplay: [String: NativeSpaceID]) -> SpaceKey {
        let displayID = DisplayManager.displayID(of: screen)
        guard let space, space != 0 else {
            return SpaceKey(space: 0, pinnedDisplay: displayID)
        }
        let shownOn = byDisplay.values.filter { $0 == space }.count
        return SpaceKey(space: space, pinnedDisplay: shownOn > 1 ? displayID : nil)
    }

    func spaceState(for key: SpaceKey) -> SpaceState {
        if let state = spaces[key] { return state }
        let state = SpaceState()
        spaces[key] = state
        return state
    }

    /// Workspace of the native space currently visible on the display.
    func activeWorkspace(for screen: NSScreen) -> Workspace {
        spaceState(for: key(for: screen)).workspace
    }

    func key(of workspace: Workspace) -> SpaceKey? {
        spaces.first { $0.value.workspace === workspace }?.key
    }

    /// The display currently showing the space, if any.
    func screen(showing key: SpaceKey) -> NSScreen? {
        let byDisplay = SpaceTracker.activeSpacesByDisplay()
        if let pinned = key.pinnedDisplay {
            guard let screen = DisplayManager.screen(withDisplayID: pinned) else { return nil }
            let current = SpaceTracker.currentSpace(for: screen, in: byDisplay)
            // The unknown-space bucket is on screen while the space stays unknown
            let shown = key.space == 0 ? current == nil : current == key.space
            return shown ? screen : nil
        }
        return NSScreen.screens.first { SpaceTracker.currentSpace(for: $0, in: byDisplay) == key.space }
    }

    /// True if the workspace belongs to a space visible on some display.
    func isVisible(_ workspace: Workspace) -> Bool {
        guard let key = key(of: workspace) else { return false }
        return screen(showing: key) != nil
    }

    /// Searches for the window across the whole model.
    func locate(_ id: WindowID) -> Location? {
        for (key, state) in spaces {
            if let managed = state.workspace.windows[id] {
                return Location(key: key, workspace: state.workspace, managed: managed)
            }
        }
        return nil
    }
}
