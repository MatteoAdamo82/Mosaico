import AppKit

/// Conversioni di coordinate e interrogazione display.
///
/// Convenzione interna di Mosaico: TUTTO in coordinate AX/CG (origine in alto
/// a sinistra dello schermo primario, Y cresce verso il basso) — le stesse di
/// kAXPositionAttribute e CGWindowList. NSScreen usa origine in basso a
/// sinistra: convertire SOLO qui.
enum DisplayManager {

    /// Altezza dello schermo primario in coordinate Cocoa (serve per il flip Y).
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// NSScreen.frame (Cocoa) → rect in coordinate AX.
    static func axRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Rect AX → coordinate Cocoa (per NSWindow). La trasformazione è
    /// involutiva: stessa formula.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Frame completo del display in coordinate AX.
    static func axFrame(of screen: NSScreen) -> CGRect {
        axRect(fromCocoa: screen.frame)
    }

    /// visibleFrame (senza menubar/Dock) in coordinate AX.
    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        axRect(fromCocoa: screen.visibleFrame)
    }

    /// Display che contiene il punto (coordinate AX); fallback: primario.
    static func screen(containingAX point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { axFrame(of: $0).contains(point) } ?? NSScreen.screens.first
    }

    /// Display che contiene il centro del rect AX.
    static func screen(containingAX rect: CGRect) -> NSScreen? {
        screen(containingAX: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Identificatore stabile del display.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// Display adiacente in direzione west/east rispetto a quello dato.
    static func screen(_ direction: Direction, of screen: NSScreen) -> NSScreen? {
        let origin = axFrame(of: screen)
        let candidates = NSScreen.screens.filter { $0 != screen }
        switch direction {
        case .west:
            return candidates
                .filter { axFrame(of: $0).midX < origin.midX }
                .max { axFrame(of: $0).midX < axFrame(of: $1).midX }
        case .east:
            return candidates
                .filter { axFrame(of: $0).midX > origin.midX }
                .min { axFrame(of: $0).midX < axFrame(of: $1).midX }
        case .north:
            return candidates
                .filter { axFrame(of: $0).midY < origin.midY }
                .max { axFrame(of: $0).midY < axFrame(of: $1).midY }
        case .south:
            return candidates
                .filter { axFrame(of: $0).midY > origin.midY }
                .min { axFrame(of: $0).midY < axFrame(of: $1).midY }
        }
    }
}
