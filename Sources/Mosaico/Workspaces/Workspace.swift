import CoreGraphics

/// Record of a managed window.
final class ManagedWindow {
    let window: AXWindow
    var isFloating = false
    var isZoomed = false

    init(window: AXWindow) {
        self.window = window
    }

    var id: WindowID { window.id }
}

/// A workspace: the tiling tree of a native space.
final class Workspace {
    let tree = BSPTree()
    /// All windows of the workspace (including floating ones).
    var windows: [WindowID: ManagedWindow] = [:]

    /// Incremented on every apply: invalidates delayed re-applies when
    /// the tree changes in the meantime.
    var layoutGeneration = 0

    func add(_ managed: ManagedWindow, near: WindowID?, leafRect: (WindowID) -> CGRect?) {
        windows[managed.id] = managed
        if !managed.isFloating {
            tree.insert(managed.id, near: near, leafRect: leafRect)
        }
    }

    @discardableResult
    func remove(_ id: WindowID) -> ManagedWindow? {
        tree.remove(id)
        return windows.removeValue(forKey: id)
    }

    /// Swaps the occupant of a tile slot without changing the layout
    /// (macOS tab took over its host window's place).
    func replace(oldID: WindowID, with managed: ManagedWindow) {
        windows.removeValue(forKey: oldID)
        windows[managed.id] = managed
        tree.rename(oldID, to: managed.id)
    }

    func setFloating(_ id: WindowID, _ floating: Bool) {
        guard let managed = windows[id] else { return }
        managed.isFloating = floating
        if floating {
            tree.remove(id)
        } else if !tree.contains(id) {
            tree.insert(id, near: nil, leafRect: { _ in managed.window.frame })
        }
    }
}
