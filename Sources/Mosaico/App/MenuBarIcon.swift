import AppKit

/// Icona menubar: mini-mosaico a suddivisione aurea, coerente con l'icona
/// dell'app. Disegnata a runtime, nitida a ogni scala.
enum MenuBarIcon {
    static let normal = make(alpha: 1.0)
    static let paused = make(alpha: 0.35)

    private static let colors: [NSColor] = [
        NSColor(srgbRed: 0.227, green: 0.525, blue: 1.0, alpha: 1),    // blu
        NSColor(srgbRed: 0.180, green: 0.769, blue: 0.714, alpha: 1),  // teal
        NSColor(srgbRed: 0.514, green: 0.220, blue: 0.925, alpha: 1),  // viola
        NSColor(srgbRed: 1.0, green: 0.745, blue: 0.043, alpha: 1),    // giallo
    ]

    private static func make(alpha: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let area = NSRect(x: 1, y: 2, width: 16, height: 14)
            let gap: CGFloat = 1
            let phi: CGFloat = 0.618

            // Suddivisione aurea a 4 piastrelle (sinistra, alto, destra+resto)
            var tiles: [NSRect] = []
            var r = area
            let w1 = r.width * phi
            tiles.append(NSRect(x: r.minX, y: r.minY, width: w1, height: r.height))
            r = NSRect(x: r.minX + w1, y: r.minY, width: r.width - w1, height: r.height)
            let h1 = r.height * phi
            tiles.append(NSRect(x: r.minX, y: r.maxY - h1, width: r.width, height: h1))
            r = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - h1)
            let w2 = r.width * phi
            tiles.append(NSRect(x: r.maxX - w2, y: r.minY, width: w2, height: r.height))
            tiles.append(NSRect(x: r.minX, y: r.minY, width: r.width - w2, height: r.height))

            for (i, tile) in tiles.enumerated() {
                let inset = tile.insetBy(dx: gap / 2, dy: gap / 2)
                let radius = min(1.5, min(inset.width, inset.height) * 0.3)
                let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
                colors[min(i, colors.count - 1)].withAlphaComponent(alpha).setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
