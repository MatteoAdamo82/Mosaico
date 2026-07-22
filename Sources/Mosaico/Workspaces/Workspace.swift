import CoreGraphics

/// Record di una finestra gestita.
final class ManagedWindow {
    let window: AXWindow
    var isFloating = false
    var isZoomed = false

    init(window: AXWindow) {
        self.window = window
    }

    var id: WindowID { window.id }
}

/// Un workspace: l'albero di tiling di uno space nativo.
final class Workspace {
    let tree = BSPTree()
    /// Tutte le finestre del workspace (anche floating).
    var windows: [WindowID: ManagedWindow] = [:]

    /// Incrementata a ogni apply: invalida i re-apply ritardati quando
    /// l'albero cambia nel frattempo.
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
