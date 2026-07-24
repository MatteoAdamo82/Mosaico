import AppKit

/// Coordinate conversions and display querying.
///
/// Mosaico internal convention: EVERYTHING in AX/CG coordinates (origin at the
/// top-left of the primary screen, Y grows downward) — the same as
/// kAXPositionAttribute and CGWindowList. NSScreen uses a bottom-left origin:
/// convert ONLY here.
enum DisplayManager {

    /// Height of the primary screen in Cocoa coordinates (needed for the Y flip).
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// NSScreen.frame (Cocoa) → rect in AX coordinates.
    static func axRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Rect AX → Cocoa coordinates (for NSWindow). The transform is
    /// involutive: same formula.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Full display frame in AX coordinates.
    static func axFrame(of screen: NSScreen) -> CGRect {
        axRect(fromCocoa: screen.frame)
    }

    /// visibleFrame (without menubar/Dock) in AX coordinates.
    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        axRect(fromCocoa: screen.visibleFrame)
    }

    /// Display containing the point (AX coordinates); fallback: primary.
    static func screen(containingAX point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { axFrame(of: $0).contains(point) } ?? NSScreen.screens.first
    }

    /// Display containing the center of the AX rect.
    static func screen(containingAX rect: CGRect) -> NSScreen? {
        screen(containingAX: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Stable display identifier.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// Adjacent display in the given direction. If no display is in that
    /// direction (e.g. stacked monitors and west/east direction), it cycles
    /// through the displays in spatial order: the commands stay usable with
    /// any arrangement.
    static func screen(_ direction: Direction, of screen: NSScreen) -> NSScreen? {
        let origin = axFrame(of: screen)
        let candidates = NSScreen.screens.filter { $0 != screen }
        guard !candidates.isEmpty else { return nil }

        let geometric: NSScreen?
        switch direction {
        case .west:
            geometric = candidates
                .filter { axFrame(of: $0).midX < origin.midX }
                .max { axFrame(of: $0).midX < axFrame(of: $1).midX }
        case .east:
            geometric = candidates
                .filter { axFrame(of: $0).midX > origin.midX }
                .min { axFrame(of: $0).midX < axFrame(of: $1).midX }
        case .north:
            geometric = candidates
                .filter { axFrame(of: $0).midY < origin.midY }
                .max { axFrame(of: $0).midY < axFrame(of: $1).midY }
        case .south:
            geometric = candidates
                .filter { axFrame(of: $0).midY > origin.midY }
                .min { axFrame(of: $0).midY < axFrame(of: $1).midY }
        }
        if let geometric { return geometric }

        // Fallback: sort by position (x, then y) and cycle
        let ordered = NSScreen.screens.sorted {
            let a = axFrame(of: $0), b = axFrame(of: $1)
            return a.midX != b.midX ? a.midX < b.midX : a.midY < b.midY
        }
        guard let index = ordered.firstIndex(of: screen) else { return nil }
        let count = ordered.count
        switch direction {
        case .west, .north:
            return ordered[(index - 1 + count) % count]
        case .east, .south:
            return ordered[(index + 1) % count]
        }
    }
}
