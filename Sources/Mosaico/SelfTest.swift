import CoreGraphics
import Foundation

/// Test del BSPTree e del preset hotkey, eseguiti con `Mosaico --selftest`.
/// (XCTest non è disponibile con i soli CommandLineTools.)
enum SelfTest {
    private static var failures = 0

    private static func check(_ condition: Bool, _ name: String) {
        if condition {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func run() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)

        func liveRect(_ tree: BSPTree) -> (WindowID) -> CGRect? {
            { id in tree.frames(in: rect, gap: 0)[id] }
        }

        // Insert second_child: [1 | 2]
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[1]!.origin.x == 0 && frames[2]!.origin.x == 500, "insert second_child")
        }

        // Orientamento dal lato lungo: foglia 500x600 → split verticale
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.insert(3, near: 2, leafRect: liveRect(tree))
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[2]!.origin.y == 0 && frames[3]!.origin.y == 300 && frames[3]!.origin.x == 500,
                  "orientamento lato lungo")
        }

        // Remove promuove il sibling
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.remove(1)
            let frames = tree.frames(in: rect, gap: 0)
            check(frames.count == 1 && frames[2] == rect, "remove promuove sibling")
        }

        // Swap
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            let before = tree.frames(in: rect, gap: 0)
            tree.swap(1, 2)
            let after = tree.frames(in: rect, gap: 0)
            check(before[1] == after[2] && before[2] == after[1], "swap")
        }

        // Warp west: 3 a sinistra di 1, 2 tutta la colonna destra
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.insert(3, near: 2, leafRect: liveRect(tree))
            tree.warp(3, onto: 1, direction: .west)
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[3]!.origin.x < frames[1]!.origin.x && frames[2]!.height == 600, "warp west")
        }

        // Rotate 270: [1 | 2] → 2 sopra, 1 sotto
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.rotate270()
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[2]!.origin.y < frames[1]!.origin.y && frames[1]!.width == 1000, "rotate 270")
        }

        // Mirror Y
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.mirrorY()
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[1]!.origin.x > frames[2]!.origin.x, "mirror Y")
        }

        // Balance
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.leaf(for: 1)!.parent!.ratio = 0.8
            tree.balance()
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[1]!.width == frames[2]!.width, "balance")
        }

        // Gap
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            let frames = tree.frames(in: rect, gap: 10)
            check(frames[2]!.origin.x - frames[1]!.maxX == 10 &&
                  frames[1]!.width + frames[2]!.width == 990, "gap")
        }

        // Adozione edge-aware: [1 | 2], trascino il bordo SINISTRO di 2
        // verso destra → lo spazio lo prende 1 (a sinistra)
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            // 2 era a x=500 w=500; ora x=600 w=400 (bordo sinistro spostato)
            tree.adoptFrame(for: 2, actual: CGRect(x: 600, y: 0, width: 400, height: 600),
                            in: rect, gap: 0)
            let frames = tree.frames(in: rect, gap: 0)
            check(abs(frames[1]!.width - 600) < 1 && abs(frames[2]!.width - 400) < 1,
                  "adozione bordo sinistro → assorbe la finestra a sinistra")
        }

        // Adozione edge-aware: [1 | 2], trascino il bordo DESTRO di 1
        // verso sinistra → lo spazio lo prende 2 (a destra)
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.adoptFrame(for: 1, actual: CGRect(x: 0, y: 0, width: 400, height: 600),
                            in: rect, gap: 0)
            let frames = tree.frames(in: rect, gap: 0)
            check(abs(frames[2]!.width - 600) < 1 && abs(frames[2]!.origin.x - 400) < 1,
                  "adozione bordo destro → assorbe la finestra a destra")
        }

        // Fallback bordo schermo: [1 | 2], trascino il bordo SINISTRO di 1
        // (non c'è nessuno a sinistra) → reagisce comunque il divisore destro
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.adoptFrame(for: 1, actual: CGRect(x: 100, y: 0, width: 400, height: 600),
                            in: rect, gap: 0)
            let frames = tree.frames(in: rect, gap: 0)
            check(abs(frames[1]!.width - 400) < 1 && abs(frames[2]!.width - 600) < 1,
                  "adozione fallback bordo schermo")
        }

        // Edge-aware annidato: [1 | 2 | 3] (3 warpato a est di 2), bordo
        // sinistro di 3 mosso a destra → assorbe 2, non 1
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.insert(3, near: 2, leafRect: liveRect(tree))
            tree.warp(3, onto: 2, direction: .east)
            let before = tree.frames(in: rect, gap: 0)
            // 3 occupa il quarto destro? verifica poi muovi il bordo sinistro di +50
            var moved = before[3]!
            moved.origin.x += 50
            moved.size.width -= 50
            tree.adoptFrame(for: 3, actual: moved, in: rect, gap: 0)
            let after = tree.frames(in: rect, gap: 0)
            check(abs(after[2]!.width - (before[2]!.width + 50)) < 1 &&
                  abs(after[1]!.width - before[1]!.width) < 1,
                  "adozione annidata → assorbe il vicino giusto")
        }

        // Preset senza duplicati
        do {
            let keys = KeyBinding.defaultPreset.map { "\($0.keyCode)-\($0.carbonModifiers)" }
            check(keys.count == Set(keys).count, "preset hotkey senza duplicati")
        }

        print(failures == 0 ? "\nTUTTI I TEST PASSANO" : "\n\(failures) TEST FALLITI")
        if failures > 0 { exit(1) }
    }
}
