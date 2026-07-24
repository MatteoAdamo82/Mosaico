import CoreGraphics

enum Orientation {
    case horizontal   // children side by side (vertical split of the space: first left, second right)
    case vertical     // children stacked (first top, second bottom)

    var flipped: Orientation { self == .horizontal ? .vertical : .horizontal }
}

/// BSP tree node. Reference type with parent pointer: simplifies
/// remove/swap/warp/neighbor.
final class BSPNode {
    weak var parent: BSPNode?
    var orientation: Orientation = .horizontal
    var ratio: CGFloat = 0.5
    var first: BSPNode?
    var second: BSPNode?
    var windowID: WindowID?    // leaves only

    var isLeaf: Bool { windowID != nil }

    init(windowID: WindowID) {
        self.windowID = windowID
    }

    init(orientation: Orientation, ratio: CGFloat = 0.5, first: BSPNode, second: BSPNode) {
        self.orientation = orientation
        self.ratio = ratio
        self.first = first
        self.second = second
        first.parent = self
        second.parent = self
    }
}

/// BSP tree of a workspace. Replicates yabai semantics:
/// insert = split of the focused leaf, new window as second_child,
/// orientation chosen from the long side of the leaf's rect.
final class BSPTree {
    private(set) var root: BSPNode?

    var isEmpty: Bool { root == nil }

    var windowIDs: [WindowID] {
        var result: [WindowID] = []
        walkLeaves { result.append($0.windowID!) }
        return result
    }

    var count: Int { windowIDs.count }

    func contains(_ id: WindowID) -> Bool {
        leaf(for: id) != nil
    }

    // MARK: - Mutations

    /// Inserts next to leaf `near` (usually the focused window);
    /// if nil, next to the last leaf. The leaf's `rect` is used to
    /// choose the orientation (long side).
    func insert(_ id: WindowID, near: WindowID?, leafRect: (WindowID) -> CGRect?) {
        guard let root else {
            self.root = BSPNode(windowID: id)
            return
        }
        guard !contains(id) else { return }

        let target: BSPNode = near.flatMap { leaf(for: $0) } ?? lastLeaf(of: root)

        let oldLeaf = BSPNode(windowID: target.windowID!)
        let newLeaf = BSPNode(windowID: id)

        let rect = leafRect(target.windowID!) ?? .zero
        let orientation: Orientation = rect.width >= rect.height ? .horizontal : .vertical

        // second_child: the new window is `second` (right or bottom)
        target.windowID = nil
        target.orientation = orientation
        target.ratio = 0.5
        target.first = oldLeaf
        target.second = newLeaf
        oldLeaf.parent = target
        newLeaf.parent = target
    }

    func remove(_ id: WindowID) {
        guard let node = leaf(for: id) else { return }
        guard let parent = node.parent else {
            root = nil
            return
        }
        let sibling = (parent.first === node) ? parent.second! : parent.first!
        // The sibling takes the parent's place
        parent.windowID = sibling.windowID
        parent.orientation = sibling.orientation
        parent.ratio = sibling.ratio
        parent.first = sibling.first
        parent.second = sibling.second
        parent.first?.parent = parent
        parent.second?.parent = parent
    }

    func swap(_ a: WindowID, _ b: WindowID) {
        guard let la = leaf(for: a), let lb = leaf(for: b) else { return }
        la.windowID = b
        lb.windowID = a
    }

    /// Warp: removes `id` and re-inserts it by splitting leaf `target`.
    /// The direction decides the split orientation and the order of the children.
    func warp(_ id: WindowID, onto target: WindowID, direction: Direction) {
        guard id != target, contains(id), let _ = leaf(for: target) else { return }
        remove(id)
        guard let targetLeaf = leaf(for: target) else { return }

        let movedLeaf = BSPNode(windowID: id)
        let stayLeaf = BSPNode(windowID: target)

        let orientation: Orientation = (direction == .west || direction == .east) ? .horizontal : .vertical
        let movedFirst = (direction == .west || direction == .north)

        targetLeaf.windowID = nil
        targetLeaf.orientation = orientation
        targetLeaf.ratio = 0.5
        targetLeaf.first = movedFirst ? movedLeaf : stayLeaf
        targetLeaf.second = movedFirst ? stayLeaf : movedLeaf
        targetLeaf.first?.parent = targetLeaf
        targetLeaf.second?.parent = targetLeaf
    }

    /// 270° rotation (counterclockwise, like yabai --rotate 270).
    /// [A|B] horizontal → B on top, A on bottom (swap + inverted ratio);
    /// A above B vertical → [A|B] horizontal (unchanged).
    func rotate270() {
        walkSplits { node in
            if node.orientation == .horizontal {
                node.orientation = .vertical
                let tmp = node.first
                node.first = node.second
                node.second = tmp
                node.ratio = 1 - node.ratio
            } else {
                node.orientation = .horizontal
            }
        }
    }

    /// Mirrors along the Y axis (swaps left/right).
    func mirrorY() {
        walkSplits { node in
            guard node.orientation == .horizontal else { return }
            let tmp = node.first
            node.first = node.second
            node.second = tmp
            node.ratio = 1 - node.ratio
        }
    }

    /// Mirrors along the X axis (swaps top/bottom).
    func mirrorX() {
        walkSplits { node in
            guard node.orientation == .vertical else { return }
            let tmp = node.first
            node.first = node.second
            node.second = tmp
            node.ratio = 1 - node.ratio
        }
    }

    func balance() {
        walkSplits { $0.ratio = 0.5 }
    }

    // MARK: - Layout

    /// Computes the leaf frames inside `rect`, with `gap` between children.
    func frames(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        guard let root else { return result }
        computeFrames(node: root, rect: rect, gap: gap, into: &result)
        return result
    }

    private func computeFrames(node: BSPNode, rect: CGRect, gap: CGFloat, into result: inout [WindowID: CGRect]) {
        if let id = node.windowID {
            result[id] = rect
            return
        }
        guard let first = node.first, let second = node.second else { return }

        let (firstRect, secondRect) = splitRects(node, rect: rect, gap: gap)
        computeFrames(node: first, rect: firstRect, gap: gap, into: &result)
        computeFrames(node: second, rect: secondRect, gap: gap, into: &result)
    }

    // MARK: - Search

    func leaf(for id: WindowID) -> BSPNode? {
        var found: BSPNode?
        walkLeaves { if $0.windowID == id { found = $0 } }
        return found
    }

    /// Adopts a real frame into the tree's ratios, accounting for WHICH
    /// edge was dragged: the divider that moves is the one on the edge's
    /// side, so the freed space is absorbed by the windows on that side.
    /// If there is no divider on that side (screen edge), fall back to the
    /// nearest divider on the other side.
    func adoptFrame(for id: WindowID, actual: CGRect, in rect: CGRect, gap: CGFloat) {
        guard let leafNode = leaf(for: id), let root else { return }
        let current = frames(in: rect, gap: gap)
        guard let expected = current[id] else { return }

        let dw = actual.width - expected.width
        if abs(dw) > 1 {
            // Left edge moved → we need the divider on the left, i.e. an
            // ancestor where our subtree is the SECOND child.
            let leadingMoved = abs(actual.minX - expected.minX) > 1
            let trailingMoved = abs(actual.maxX - expected.maxX) > 1
            let wantSecondChild: Bool? = (leadingMoved && !trailingMoved) ? true
                                       : (trailingMoved && !leadingMoved) ? false
                                       : nil
            adoptDelta(dw, axis: .horizontal, nodeIsSecondChild: wantSecondChild,
                       from: leafNode, root: root, rect: rect, gap: gap)
        }

        let dh = actual.height - expected.height
        if abs(dh) > 1 {
            let topMoved = abs(actual.minY - expected.minY) > 1
            let bottomMoved = abs(actual.maxY - expected.maxY) > 1
            let wantSecondChild: Bool? = (topMoved && !bottomMoved) ? true
                                       : (bottomMoved && !topMoved) ? false
                                       : nil
            adoptDelta(dh, axis: .vertical, nodeIsSecondChild: wantSecondChild,
                       from: leafNode, root: root, rect: rect, gap: gap)
        }
    }

    private func adoptDelta(_ delta: CGFloat, axis: Orientation, nodeIsSecondChild: Bool?,
                            from leafNode: BSPNode, root: BSPNode,
                            rect: CGRect, gap: CGFloat) {
        guard abs(delta) > 1 else { return }

        // Walk up looking for an ancestor with the right axis AND the right
        // side (if required); the first with the right axis acts as fallback.
        var child: BSPNode = leafNode
        var ancestor = leafNode.parent
        var fallback: (split: BSPNode, child: BSPNode)?
        var chosen: (split: BSPNode, child: BSPNode)?
        while let node = ancestor {
            if node.orientation == axis {
                if fallback == nil { fallback = (node, child) }
                let isSecond = node.second === child
                if nodeIsSecondChild == nil || isSecond == nodeIsSecondChild {
                    chosen = (node, child)
                    break
                }
            }
            child = node
            ancestor = node.parent
        }

        guard let (split, splitChild) = chosen ?? fallback,
              let splitRect = nodeRect(of: split, node: root, rect: rect, gap: gap) else { return }

        let usable = (axis == .horizontal ? splitRect.width : splitRect.height) - gap
        guard usable > 0 else { return }

        let isFirst = split.first === splitChild
        let firstSpan = usable * split.ratio
        let newFirstSpan = isFirst ? firstSpan + delta : firstSpan - delta
        split.ratio = max(0.1, min(0.9, newFirstSpan / usable))
    }

    /// Rect of an internal node (same geometry as computeFrames).
    private func nodeRect(of target: BSPNode, node: BSPNode, rect: CGRect, gap: CGFloat) -> CGRect? {
        if node === target { return rect }
        guard let first = node.first, let second = node.second else { return nil }
        let (firstRect, secondRect) = splitRects(node, rect: rect, gap: gap)
        return nodeRect(of: target, node: first, rect: firstRect, gap: gap)
            ?? nodeRect(of: target, node: second, rect: secondRect, gap: gap)
    }

    private func splitRects(_ node: BSPNode, rect: CGRect, gap: CGFloat) -> (CGRect, CGRect) {
        var firstRect = rect
        var secondRect = rect
        switch node.orientation {
        case .horizontal:
            let w = (rect.width - gap) * node.ratio
            firstRect.size.width = w
            secondRect.origin.x = rect.origin.x + w + gap
            secondRect.size.width = rect.width - w - gap
        case .vertical:
            let h = (rect.height - gap) * node.ratio
            firstRect.size.height = h
            secondRect.origin.y = rect.origin.y + h + gap
            secondRect.size.height = rect.height - h - gap
        }
        return (firstRect, secondRect)
    }

    // MARK: - Walk

    private func walkLeaves(_ visit: (BSPNode) -> Void) {
        guard let root else { return }
        var stack = [root]
        while let node = stack.popLast() {
            if node.isLeaf {
                visit(node)
            } else {
                if let s = node.second { stack.append(s) }
                if let f = node.first { stack.append(f) }
            }
        }
    }

    private func walkSplits(_ visit: (BSPNode) -> Void) {
        guard let root else { return }
        var stack = [root]
        while let node = stack.popLast() {
            if !node.isLeaf {
                visit(node)
                if let s = node.second { stack.append(s) }
                if let f = node.first { stack.append(f) }
            }
        }
    }

    private func lastLeaf(of node: BSPNode) -> BSPNode {
        var current = node
        while let second = current.second {
            current = second
        }
        return current
    }
}
