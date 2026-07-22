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

    /// Display adiacente nella direzione data. Se nessun display sta in
    /// quella direzione (es. monitor impilati e direzione ovest/est), cicla
    /// tra i display in ordine spaziale: i comandi restano utilizzabili con
    /// qualsiasi disposizione.
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

        // Fallback: ordina per posizione (x, poi y) e cicla
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
