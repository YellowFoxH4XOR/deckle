// Generates AppIcon.icns from the "1c — The Letter" concept in the Deckle
// design project: a warm paper squircle with fine grain, a letterpress
// italic serif "d", and a vermillion dot at the lower right.
// Run: swift scripts/GenerateIcon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconsetPath = "\(outputDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// Design palette (from Deckle Icons.dc.html, option 1c)
let paper = NSColor(srgbRed: 0.945, green: 0.937, blue: 0.914, alpha: 1) // #F1EFE9
let ink = NSColor(srgbRed: 0.098, green: 0.090, blue: 0.075, alpha: 1)   // #191713
let vermillion = NSColor(srgbRed: 0.702, green: 0.290, blue: 0.133, alpha: 1) // #B34A22

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's icon grid: content occupies ~82% of the canvas.
    let margin = s * 0.093
    let bg = NSRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let unit = bg.width / 160 // design file is authored on a 160pt grid
    let squircle = NSBezierPath(
        roundedRect: bg,
        xRadius: 36 * unit,
        yRadius: 36 * unit
    )

    paper.setFill()
    squircle.fill()

    // Paper grain: deterministic speckle field, clipped to the squircle
    // (stands in for the design's feTurbulence multiply layer).
    var seed: UInt64 = 0x5EED
    func rand() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 40) / CGFloat(1 << 24)
    }
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    for _ in 0..<(pixels * 4) {
        let dark = rand() > 0.5
        (dark ? ink : NSColor.white)
            .withAlphaComponent(0.04 + rand() * 0.07)
            .setFill()
        let r = max(0.5, s / 512) * (0.5 + rand())
        NSBezierPath(ovalIn: NSRect(
            x: bg.minX + rand() * bg.width,
            y: bg.minY + rand() * bg.height,
            width: r, height: r
        )).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    // The letterpress "d" — Newsreader in the design; Georgia is the
    // design's own fallback and ships with macOS.
    let font = NSFont(name: "Georgia-BoldItalic", size: 122 * unit)
        ?? NSFont.boldSystemFont(ofSize: 122 * unit)
    let letter = NSAttributedString(string: "d", attributes: [
        .font: font,
        .foregroundColor: ink,
    ])
    let size = letter.size()
    // Centered, then nudged per the design's translate(-8px, -6px)
    // (CSS -y is upward-in-Cocoa here since we mirror the visual result).
    letter.draw(at: NSPoint(
        x: bg.midX - size.width / 2 - 8 * unit,
        y: bg.midY - size.height / 2 + 6 * unit
    ))

    // Vermillion dot, lower right (right: 36, bottom: 36, d = 14 on the grid)
    vermillion.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: bg.maxX - (36 + 14) * unit,
        y: bg.minY + 36 * unit,
        width: 14 * unit, height: 14 * unit
    )).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

for size in [16, 32, 128, 256, 512] {
    writePNG(drawIcon(pixels: size), to: "\(iconsetPath)/icon_\(size)x\(size).png")
    writePNG(drawIcon(pixels: size * 2), to: "\(iconsetPath)/icon_\(size)x\(size)@2x.png")
}

let iconutil = Process()
iconutil.launchPath = "/usr/bin/iconutil"
iconutil.arguments = ["-c", "icns", iconsetPath, "-o", "\(outputDir)/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(outputDir)/AppIcon.icns")
