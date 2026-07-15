import AppKit
import CoreGraphics

/// Generates tileable paper-grain images, mimicking SVG
/// `feTurbulence type="fractalNoise" baseFrequency="1.5" numOctaves="3"`:
/// several octaves of tileable value noise summed together, desaturated, then
/// mapped to translucent dark/light speckles that composite over screen
/// content like a paper sheet would.
enum TextureRenderer {
    /// Cached tiles keyed by preset id.
    private static var tileCache: [String: NSImage] = [:]
    private static var previewCache: [String: NSImage] = [:]

    /// A small seamless tile; Core Graphics pattern fill repeats it across the
    /// screen, so a huge display costs the same memory as this one tile.
    static func tile(for preset: TexturePreset) -> NSImage {
        if let cached = tileCache[preset.id] { return cached }

        let pixelSize = 256
        let noise = fractalNoise(size: pixelSize, preset: preset)

        var pixels = [UInt8](repeating: 0, count: pixelSize * pixelSize * 4)
        let dark = preset.darkColor.usingColorSpace(.sRGB)!
        let light = preset.lightColor.usingColorSpace(.sRGB)!

        for i in 0..<(pixelSize * pixelSize) {
            let delta = noise[i] - 0.5
            let color: NSColor
            let alpha: Float
            if delta < 0 {
                color = dark
                alpha = min(1, -delta * 2) * preset.darkStrength
            } else {
                color = light
                alpha = min(1, delta * 2) * preset.lightStrength
            }
            // Premultiplied RGBA
            let a = CGFloat(alpha)
            pixels[i * 4 + 0] = UInt8(color.redComponent * a * 255)
            pixels[i * 4 + 1] = UInt8(color.greenComponent * a * 255)
            pixels[i * 4 + 2] = UInt8(color.blueComponent * a * 255)
            pixels[i * 4 + 3] = UInt8(a * 255)
        }

        let image = pixels.withUnsafeMutableBytes { buffer -> NSImage in
            let context = CGContext(
                data: buffer.baseAddress,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: pixelSize * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let cgImage = context.makeImage()!
            // Report the tile at half its pixel size so grain stays fine on
            // Retina displays (2 device pixels per point).
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: pixelSize / 2, height: pixelSize / 2)
            )
        }

        tileCache[preset.id] = image
        return image
    }

    /// Swatch used in the menu texture picker: the texture drawn over a plain
    /// background, boosted so it is recognizable at thumbnail size.
    static func preview(for preset: TexturePreset, size: CGSize) -> NSImage {
        let key = "\(preset.id)-\(Int(size.width))x\(Int(size.height))"
        if let cached = previewCache[key] { return cached }

        let patternTile = tile(for: preset)
        let backdrop: NSColor = preset.isDark
            ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : .white
        let image = NSImage(size: size, flipped: false) { rect in
            backdrop.setFill()
            rect.fill()
            preset.tint
                .withAlphaComponent(min(0.9, preset.tintAlpha * 1.7))
                .setFill()
            rect.fill(using: .sourceOver)
            NSColor(patternImage: patternTile).setFill()
            rect.fill(using: .sourceOver)
            return true
        }
        previewCache[key] = image
        return image
    }

    // MARK: - Noise

    /// Sums the preset's octaves of tileable value noise (plus optional weave
    /// modulation) into a [0, 1] field.
    private static func fractalNoise(size: Int, preset: TexturePreset) -> [Float] {
        var rng = SplitMix64(seed: stableSeed(preset.id))
        var out = [Float](repeating: 0, count: size * size)
        let totalWeight = preset.octaves.reduce(Float(0)) { $0 + $1.weight }

        for octave in preset.octaves {
            let layer = valueNoise(size: size, cell: octave.cell, rng: &rng)
            let w = octave.weight / totalWeight
            for i in 0..<out.count {
                out[i] += layer[i] * w
            }
        }

        if let weave = preset.weave {
            let k = 2 * Float.pi / Float(weave.period)
            for y in 0..<size {
                let sy = sin(Float(y) * k)
                for x in 0..<size {
                    let sx = sin(Float(x) * k)
                    let i = y * size + x
                    out[i] = min(1, max(0, out[i] + (sx + sy) * 0.5 * weave.amplitude))
                }
            }
        }
        return out
    }

    /// Tileable value noise: random values on a coarse grid, smoothly
    /// interpolated, with indices wrapping at the edges (the equivalent of
    /// feTurbulence's stitchTiles="stitch").
    private static func valueNoise(size: Int, cell: Int, rng: inout SplitMix64) -> [Float] {
        if cell <= 1 {
            return (0..<size * size).map { _ in rng.unitFloat() }
        }
        let g = max(1, size / cell)
        var grid = [Float](repeating: 0, count: g * g)
        for i in 0..<grid.count { grid[i] = rng.unitFloat() }

        func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }

        var out = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let fy = Float(y) / Float(cell)
            let y0 = Int(fy) % g
            let y1 = (y0 + 1) % g
            let ty = smooth(fy - fy.rounded(.down))
            for x in 0..<size {
                let fx = Float(x) / Float(cell)
                let x0 = Int(fx) % g
                let x1 = (x0 + 1) % g
                let tx = smooth(fx - fx.rounded(.down))
                let a = grid[y0 * g + x0]
                let b = grid[y0 * g + x1]
                let c = grid[y1 * g + x0]
                let d = grid[y1 * g + x1]
                let top = a + (b - a) * tx
                let bottom = c + (d - c) * tx
                out[y * size + x] = top + (bottom - top) * ty
            }
        }
        return out
    }

    /// djb2 hash — deterministic across launches, unlike Swift's hashValue.
    private static func stableSeed(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }
}

/// Small deterministic RNG so a texture looks identical on every launch.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unitFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
