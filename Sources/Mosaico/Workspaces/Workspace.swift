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
