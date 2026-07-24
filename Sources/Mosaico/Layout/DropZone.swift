import CoreGraphics

enum DropZoneKind: Equatable {
    case swap
    case warp(Direction)
}

/// Pure geometry of the drop zones (yabai-style): center (30–70%) → swap;
/// dominant half → warp in that direction, with the rect to highlight.
enum DropZone {
    static func resolve(point: CGPoint, in frame: CGRect) -> (kind: DropZoneKind, highlight: CGRect) {
        let rx = (point.x - frame.minX) / frame.width
        let ry = (point.y - frame.minY) / frame.height

        if (0.3...0.7).contains(rx) && (0.3...0.7).contains(ry) {
            return (.swap, frame)
        }
        if abs(rx - 0.5) > abs(ry - 0.5) {
            let direction: Direction = rx < 0.5 ? .west : .east
            var half = frame
            half.size.width /= 2
            if direction == .east { half.origin.x = frame.midX }
            return (.warp(direction), half)
        }
        let direction: Direction = ry < 0.5 ? .north : .south
        var half = frame
        half.size.height /= 2
        if direction == .south { half.origin.y = frame.midY }
        return (.warp(direction), half)
    }
}
