import CoreGraphics

/// Record di una finestra gestita.
final class ManagedWindow {
    let window: AXWindow
    var isFloating = false
    var isZoomed = false
    /// Frame reale salvato quando la finestra è parcheggiata (workspace nascosto)
    /// o prima di zoom/float, per il ripristino.
    var savedFrame: CGRect?
    var floatFrame: CGRect?

    init(window: AXWindow) {
        self.window = window
    }

    var id: WindowID { window.id }
}

/// Un workspace virtuale (1..7) su un display.
final class Workspace {
    let index: Int
    let tree = BSPTree()
    /// Tutte le finestre del workspace (anche floating).
    var windows: [WindowID: ManagedWindow] = [:]

    /// Incrementata a ogni apply: invalida i re-apply ritardati quando
    /// l'albero cambia nel frattempo.
    var layoutGeneration = 0

    init(index: Int) {
        self.index = index
    }

    var isEmpty: Bool { windows.isEmpty }

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
