import AppKit

/// Icona menubar: 3 rettangoli in proporzione aurea (come l'icona app),
/// monocromatica template — si adatta a menubar chiara/scura.
enum MenuBarIcon {
    static let normal = make(alpha: 1.0)
    static let paused = make(alpha: 0.35)

    private static func make(alpha: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.withAlphaComponent(alpha).setFill()

            // Canvas 16x14 centrato; colonna sinistra 61.8%, destra divisa
            // in alto (61.8%) e basso. Coordinate intere: niente sbavature.
            // A: sinistra 9x14 — B: destra alto 5x8 — C: destra basso 5x4
            let a = NSRect(x: 1, y: 2, width: 9, height: 14)
            let b = NSRect(x: 12, y: 8, width: 5, height: 8)
            let c = NSRect(x: 12, y: 2, width: 5, height: 4)

            for rect in [a, b, c] {
                NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
