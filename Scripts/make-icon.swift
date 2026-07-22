#!/usr/bin/env swift
// Genera Resources/AppIcon.icns: piastrelle in suddivisione aurea
// (stile Fibonacci) su squircle scuro. Uso: swift Scripts/make-icon.swift

import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// Palette "mosaico": dal blu della piastrella grande ai toni caldi delle piccole
let tileColors: [NSColor] = [
    color(0x3A86FF),  // blu — piastrella grande
    color(0x2EC4B6),  // teal
    color(0x8338EC),  // viola
    color(0xFFBE0B),  // giallo
    color(0xFF006E),  // magenta — la più piccola
]

let bgTop = color(0x1B2A4A)
let bgBottom = color(0x0F1B33)

/// Suddivisione a spirale aurea di un rettangolo: a ogni passo si stacca
/// una cella al 61.8% ruotando il lato (sinistra, alto, destra, basso, …).
func goldenTiles(in rect: NSRect, cuts: Int) -> [NSRect] {
    let phi: CGFloat = 0.618
    var tiles: [NSRect] = []
    var r = rect
    for i in 0..<cuts {
        switch i % 4 {
        case 0:  // stacca a sinistra
            let w = r.width * phi
            tiles.append(NSRect(x: r.minX, y: r.minY, width: w, height: r.height))
            r = NSRect(x: r.minX + w, y: r.minY, width: r.width - w, height: r.height)
        case 1:  // stacca in alto
            let h = r.height * phi
            tiles.append(NSRect(x: r.minX, y: r.maxY - h, width: r.width, height: h))
            r = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - h)
        case 2:  // stacca a destra
            let w = r.width * phi
            tiles.append(NSRect(x: r.maxX - w, y: r.minY, width: w, height: r.height))
            r = NSRect(x: r.minX, y: r.minY, width: r.width - w, height: r.height)
        default: // stacca in basso
            let h = r.height * phi
            tiles.append(NSRect(x: r.minX, y: r.minY, width: r.width, height: h))
            r = NSRect(x: r.minX, y: r.minY + h, width: r.width, height: r.height - h)
        }
    }
    tiles.append(r)
    return tiles
}

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)

    // Squircle di sfondo secondo la griglia icone macOS (824/1024, centrato)
    let margin = s * 100 / 1024
    let bg = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let bgPath = NSBezierPath(roundedRect: bg, xRadius: bg.width * 0.2237, yRadius: bg.width * 0.2237)
    NSGradient(starting: bgTop, ending: bgBottom)!.draw(in: bgPath, angle: -90)

    // Piastrelle auree con gap (come i gap del tiling)
    let pad = bg.width * 0.075
    let gap = bg.width * 0.028
    let tileRadius = bg.width * 0.045
    let area = bg.insetBy(dx: pad, dy: pad)

    for (i, tile) in goldenTiles(in: area, cuts: 4).enumerated() {
        let inset = tile.insetBy(dx: gap / 2, dy: gap / 2)
        // Raggio proporzionato alla piastrella: le piccole non diventano pillole
        let radius = min(tileRadius, min(inset.width, inset.height) * 0.28)
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        tileColors[min(i, tileColors.count - 1)].setFill()
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Iconset completo per iconutil
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = scriptDir.deletingLastPathComponent()
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for variant in variants {
    let rep = drawIcon(pixels: variant.pixels)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)

print(task.terminationStatus == 0 ? "AppIcon.icns generata" : "iconutil fallito")
