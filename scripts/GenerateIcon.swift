// Generates AppIcon.icns in the modern macOS style: a warm gradient squircle
// holding a slightly rotated paper sheet with a folded corner, fine grain,
// and suggested text lines. Run: swift scripts/GenerateIcon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let iconsetPath = "\(outputDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> CGImage {
    let s = CGFloat(pixels)
    let context = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Apple's icon grid: content occupies ~82% of the canvas.
    let margin = s * 0.093
    let bg = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let radius = bg.width * 0.225
    let squircle = CGPath(roundedRect: bg, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Background: warm cream gradient
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(srgbRed: 0.955, green: 0.905, blue: 0.800, alpha: 1),
            CGColor(srgbRed: 0.860, green: 0.770, blue: 0.610, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: bg.midX, y: bg.maxY),
        end: CGPoint(x: bg.midX, y: bg.minY),
        options: []
    )

    var seed: UInt64 = 0x5EED
    func rand() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 40) / CGFloat(1 << 24)
    }

    // Faint grain across the background
    for _ in 0..<(pixels * 3) {
        let dark = rand() > 0.5
        context.setFillColor(CGColor(
            srgbRed: dark ? 0.45 : 1.0, green: dark ? 0.38 : 0.98,
            blue: dark ? 0.28 : 0.93, alpha: 0.05 + rand() * 0.06
        ))
        let r = max(0.5, s / 512) * (0.5 + rand())
        context.fillEllipse(in: CGRect(
            x: bg.minX + rand() * bg.width,
            y: bg.minY + rand() * bg.height,
            width: r, height: r
        ))
    }
    context.restoreGState()

    // Paper sheet, slightly rotated, with shadow and folded top-right corner
    context.saveGState()
    context.translateBy(x: s / 2, y: s / 2)
    context.rotate(by: -4 * .pi / 180)
    let w = bg.width * 0.60
    let h = bg.height * 0.70
    let fold = w * 0.22
    let sheet = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)

    let sheetPath = CGMutablePath()
    sheetPath.move(to: CGPoint(x: sheet.minX, y: sheet.minY))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY - fold))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY))
    sheetPath.addLine(to: CGPoint(x: sheet.minX, y: sheet.maxY))
    // Deckled left edge — the feathered, irregular edge of handmade paper
    // that the app is named after.
    let steps = 18
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let y = sheet.maxY - t * sheet.height
        let x = i == steps ? sheet.minX : sheet.minX + (rand() - 0.5) * w * 0.05
        sheetPath.addLine(to: CGPoint(x: x, y: y))
    }
    sheetPath.closeSubpath()

    context.setShadow(
        offset: CGSize(width: 0, height: -s * 0.015),
        blur: s * 0.035,
        color: CGColor(gray: 0, alpha: 0.30)
    )
    context.addPath(sheetPath)
    context.setFillColor(CGColor(srgbRed: 0.995, green: 0.985, blue: 0.965, alpha: 1))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // Grain on the sheet
    context.saveGState()
    context.addPath(sheetPath)
    context.clip()
    for _ in 0..<(pixels * 4) {
        let dark = rand() > 0.5
        context.setFillColor(CGColor(
            srgbRed: dark ? 0.55 : 1.0, green: dark ? 0.48 : 0.99,
            blue: dark ? 0.38 : 0.95, alpha: 0.06 + rand() * 0.08
        ))
        let r = max(0.5, s / 512) * (0.5 + rand())
        context.fillEllipse(in: CGRect(
            x: sheet.minX + rand() * sheet.width,
            y: sheet.minY + rand() * sheet.height,
            width: r, height: r
        ))
    }
    context.restoreGState()

    // Suggested text lines
    let lineColor = CGColor(srgbRed: 0.72, green: 0.65, blue: 0.52, alpha: 0.85)
    let lineHeight = h * 0.045
    let pad = w * 0.14
    let widths: [CGFloat] = [0.48, 0.72, 0.72, 0.72, 0.55]
    for (i, frac) in widths.enumerated() {
        let y = sheet.maxY - h * 0.22 - CGFloat(i) * h * 0.13
        let lineRect = CGRect(
            x: sheet.minX + pad, y: y,
            width: (w - pad * 2) * frac, height: lineHeight
        )
        context.addPath(CGPath(
            roundedRect: lineRect,
            cornerWidth: lineHeight / 2, cornerHeight: lineHeight / 2,
            transform: nil
        ))
        // First line reads as a heading: slightly darker
        context.setFillColor(i == 0
            ? CGColor(srgbRed: 0.55, green: 0.47, blue: 0.34, alpha: 0.9)
            : lineColor)
        context.fillPath()
    }

    // Folded corner flap
    context.move(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY))
    context.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY - fold))
    context.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.maxY - fold))
    context.closePath()
    context.setFillColor(CGColor(srgbRed: 0.88, green: 0.82, blue: 0.71, alpha: 1))
    context.fillPath()

    context.restoreGState()
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
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
