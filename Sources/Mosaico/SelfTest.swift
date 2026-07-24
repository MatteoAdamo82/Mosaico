import CoreGraphics
import Foundation

/// Tests for the BSPTree and the hotkey preset, run with `Mosaico --selftest`.
/// (XCTest is not available with only CommandLineTools.)
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

        // Orientation from the long side: 500x600 leaf → vertical split
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.insert(3, near: 2, leafRect: liveRect(tree))
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[2]!.origin.y == 0 && frames[3]!.origin.y == 300 && frames[3]!.origin.x == 500,
                  "long side orientation")
        }

        // Remove promotes the sibling
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.remove(1)
            let frames = tree.frames(in: rect, gap: 0)
            check(frames.count == 1 && frames[2] == rect, "remove promotes sibling")
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

        // Warp west: 3 to the left of 1, 2 the whole right column
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.insert(3, near: 2, leafRect: liveRect(tree))
            tree.warp(3, onto: 1, direction: .west)
            let frames = tree.frames(in: rect, gap: 0)
            check(frames[3]!.origin.x < frames[1]!.origin.x && frames[2]!.height == 600, "warp west")
        }

        // Rotate 270: [1 | 2] → 2 on top, 1 below
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

        // Edge-aware adoption: [1 | 2], I drag the LEFT edge of 2
        // to the right → the space is taken by 1 (on the left)
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            // 2 was at x=500 w=500; now x=600 w=400 (left edge moved)
            tree.adoptFrame(for: 2, actual: CGRect(x: 600, y: 0, width: 400, height: 600),
                            in: rect, gap: 0)
            let frames = tree.frames(in: rect, gap: 0)
            check(abs(frames[1]!.width - 600) < 1 && abs(frames[2]!.width - 400) < 1,
                  "left edge adoption → absorbs the window on the left")
        }

        // Edge-aware adoption: [1 | 2], I drag the RIGHT edge of 1
        // to the left → the space is taken by 2 (on the right)
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.adoptFrame(for: 1, actual: CGRect(x: 0, y: 0, width: 400, height: 600),
                            in: rect, gap: 0)
            let frames = tree.frames(in: rect, gap: 0)
            check(abs(frames[2]!.width - 600) < 1 && abs(frames[2]!.origin.x - 400) < 1,
                  "right edge adoption → absorbs the window on the right")
        }

        // Screen edge fallback: [1 | 2], I drag the LEFT edge of 1
        // (there is nobody on the left) → the right divider reacts anyway
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.adoptFrame(for: 1, actual: CGRect(x: 100, y: 0, width: 400, height: 600),
                            in: rect, gap: 0)
            let frames = tree.frames(in: rect, gap: 0)
            check(abs(frames[1]!.width - 400) < 1 && abs(frames[2]!.width - 600) < 1,
                  "screen edge fallback adoption")
        }

        // Nested edge-aware: [1 | 2 | 3] (3 warped east of 2), left
        // edge of 3 moved right → absorbs 2, not 1
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.insert(3, near: 2, leafRect: liveRect(tree))
            tree.warp(3, onto: 2, direction: .east)
            let before = tree.frames(in: rect, gap: 0)
            // Does 3 occupy the right quarter? verify, then move the left edge by +50
            var moved = before[3]!
            moved.origin.x += 50
            moved.size.width -= 50
            tree.adoptFrame(for: 3, actual: moved, in: rect, gap: 0)
            let after = tree.frames(in: rect, gap: 0)
            check(abs(after[2]!.width - (before[2]!.width + 50)) < 1 &&
                  abs(after[1]!.width - before[1]!.width) < 1,
                  "nested adoption → absorbs the correct neighbor")
        }

        // Vertical axis adoption: 1 above 2 (after rotate), bottom edge of 1
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            tree.rotate270()   // 2 on top, 1 below
            let before = tree.frames(in: rect, gap: 0)
            // Raise the top edge of 1 (which borders 2) by 60
            var moved = before[1]!
            moved.origin.y -= 60
            moved.size.height += 60
            tree.adoptFrame(for: 1, actual: moved, in: rect, gap: 0)
            let after = tree.frames(in: rect, gap: 0)
            check(abs(after[1]!.height - (before[1]!.height + 60)) < 1 &&
                  abs(after[2]!.height - (before[2]!.height - 60)) < 1,
                  "vertical axis adoption")
        }

        // Warp in the 4 directions
        do {
            func warped(_ direction: Direction) -> [WindowID: CGRect] {
                let tree = BSPTree()
                tree.insert(1, near: nil, leafRect: liveRect(tree))
                tree.insert(2, near: 1, leafRect: liveRect(tree))
                tree.insert(3, near: 2, leafRect: liveRect(tree))
                tree.warp(3, onto: 1, direction: direction)
                return tree.frames(in: rect, gap: 0)
            }
            let west = warped(.west)
            check(west[3]!.minX < west[1]!.minX, "warp west")
            let east = warped(.east)
            check(east[3]!.minX > east[1]!.minX, "warp east")
            let north = warped(.north)
            check(north[3]!.minY < north[1]!.minY, "warp north")
            let south = warped(.south)
            check(south[3]!.minY > south[1]!.minY, "warp south")
        }

        // Drop zone: center → swap, half → warp with correct highlight
        do {
            let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
            let center = DropZone.resolve(point: CGPoint(x: 300, y: 250), in: frame)
            check(center.kind == .swap && center.highlight == frame, "drop zone center → swap")

            let west = DropZone.resolve(point: CGPoint(x: 120, y: 250), in: frame)
            check(west.kind == .warp(.west) && west.highlight.width == 200 && west.highlight.minX == 100,
                  "drop zone left → warp west")

            let south = DropZone.resolve(point: CGPoint(x: 300, y: 390), in: frame)
            check(south.kind == .warp(.south) && south.highlight.minY == 250,
                  "drop zone bottom → warp south")
        }

        // Disposition rules (pure function)
        do {
            func traits(_ mutate: (inout WindowTraits) -> Void) -> WindowTraits {
                var t = WindowTraits(role: "AXWindow", subrole: "AXStandardWindow")
                mutate(&t)
                return t
            }
            func disp(_ t: WindowTraits, apps: [String] = [], rules: [WindowRule] = []) -> WindowDisposition {
                RulesEngine.disposition(traits: t, excludedBundleIDs: apps, excludedWindowRules: rules)
            }
            check(disp(traits { _ in }) == .tile, "rules: standard → tile")
            check(disp(traits { $0.subrole = "AXDialog" }) == .float, "rules: dialog → float")
            check(disp(traits { $0.isResizable = false }) == .float, "rules: non-resizable → float")
            check(disp(traits { $0.cgLayer = 3 }) == .ignore, "rules: floating layer → ignore")
            check(disp(traits { $0.title = "Picture in Picture" }) == .ignore, "rules: PiP → ignore")
            check(disp(traits { $0.bundleID = "com.x" }, apps: ["com.x"]) == .ignore, "rules: excluded app → ignore")
            check(disp(traits { $0.bundleID = "com.x"; $0.title = "T" },
                       rules: [WindowRule(bundleID: "com.x", title: "T")]) == .ignore,
                  "rules: excluded window → ignore")
            check(disp(traits { $0.hasWindowParent = true }) == .ignore, "rules: attached sheet → ignore")
        }

        // Shortcut rendering
        do {
            let binding = KeyBinding.defaultPreset.first { $0.command == .rotate }!
            check(binding.displayString == "⌥⇧R", "displayString ⌥⇧R for rotate")
        }

        // A degenerate frame (failed AX read) must never be adopted
        do {
            let tree = BSPTree()
            tree.insert(1, near: nil, leafRect: liveRect(tree))
            tree.insert(2, near: 1, leafRect: liveRect(tree))
            let before = tree.frames(in: rect, gap: 0)
            tree.adoptFrame(for: 2, actual: .zero, in: rect, gap: 0)
            tree.adoptFrame(for: 1, actual: CGRect(x: 0, y: 0, width: 0, height: 600), in: rect, gap: 0)
            let after = tree.frames(in: rect, gap: 0)
            check(before[1] == after[1] && before[2] == after[2],
                  "degenerate frame is not adopted")
        }

        // Preset without duplicates
        do {
            let keys = KeyBinding.defaultPreset.map { "\($0.keyCode)-\($0.carbonModifiers)" }
            check(keys.count == Set(keys).count, "hotkey preset without duplicates")
        }

        print(failures == 0 ? "\nALL TESTS PASS" : "\n\(failures) TESTS FAILED")
        if failures > 0 { exit(1) }
    }
}
