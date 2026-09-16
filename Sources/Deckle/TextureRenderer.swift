import AppKit
import Accelerate
import CoreGraphics

/// Generates tileable paper-grain images.
///
/// Versioned procedural engines render a preset's grain, selected by
/// `TexturePreset.engineVersion`:
///
/// - `.legacy` mimics SVG `feTurbulence type="fractalNoise" baseFrequency="1.5"
///   numOctaves="3"`: several octaves of tileable value noise summed together,
///   desaturated, then mapped to translucent dark/light speckles. Byte-for-byte
///   identical to the original generator — version-less saved custom papers
///   depend on this never changing.
/// - `.spectral` synthesizes a real-valued periodic field via a random-phase
///   frequency spectrum and an inverse 2D FFT (`vDSP_fft2d_zip`), then layers
///   in a deterministic woven crosshatch, toroidally wrapped elongated fiber
///   splats, and sparse flecks. Existing built-in presets stay on this path.
/// - `.spectralPlus` starts from the v2 spectrum and adds oriented,
///   glare-reducing fiber bundles plus multi-octave surface roughness for new
///   custom papers and advanced built-ins.
///
/// All engines map their [0, 1] field to translucent dark/light speckles the
/// same way, and all composite over screen content like a paper sheet would.
enum TextureRenderer {
    /// Logical size (in grid points) of the field both engines synthesize.
    /// Legacy renders it 1:1 as 256 pixels; spectral renders it as 256 points
    /// backing-scale-aware (256 px at 1x, 512 px at 2x).
    private static let fieldSize = 256

    // MARK: - Caches

    /// Diagnostic counters for the renderer's caches, exposed so tests can
    /// assert on cache behavior (hits, misses, bypass) without reaching into
    /// private storage.
    struct CacheMetrics: Equatable {
        var fieldHits = 0
        var fieldMisses = 0
        var tileHits = 0
        var tileMisses = 0
        var compositeHits = 0
        var compositeMisses = 0
        var previewHits = 0
        var previewMisses = 0
    }

    static private(set) var cacheMetrics = CacheMetrics()

    /// Small bounded LRU caches, all confined to the main thread by existing
    /// call patterns (menu UI, overlay windows) — no locking, no actors.
    private static var fieldCache = LRUCache<String, [Float]>(capacity: 16)
    private static var tileCache = LRUCache<String, NSImage>(capacity: 16)
    private static var compositeCache = LRUCache<String, NSImage>(capacity: 8)
    private static var previewCache = LRUCache<String, NSImage>(capacity: 24)

    /// Clears every cache and resets diagnostic counters. Exposed for tests
    /// that need isolation between cases.
    static func resetCaches() {
        fieldCache.removeAll()
        tileCache.removeAll()
        compositeCache.removeAll()
        previewCache.removeAll()
        cacheMetrics = CacheMetrics()
    }

    /// User-tunable grain adjustments, applied on top of any preset.
    /// `scale` multiplies the noise cell sizes (snapped to powers of two so
    /// tiles stay seamless); `strength` multiplies speckle visibility.
    struct GrainAdjustments: Equatable {
        var scale: Double = 1.0
        var strength: Double = 1.0
        var matte: Double = 0.0

        static let none = GrainAdjustments()
        /// Key for the synthesized noise field. Only scale changes its shape.
        var fieldCacheKey: String {
            "s\(scale.bitPattern)"
        }

        /// Key for the translucent grain tile. Strength changes pixel alpha,
        /// but matte only affects the later tint composite.
        var tileCacheKey: String {
            "\(fieldCacheKey)-k\(strength.bitPattern)"
        }

        /// Key for the final overlay tile, including the tint-only matte pass.
        /// Exact bit patterns prevent stale output for sub-step changes.
        var cacheKey: String {
            "\(tileCacheKey)-m\(matte.bitPattern)"
        }
    }

    /// Snaps an arbitrary backing scale factor to the only two resolutions
    /// the renderer supports: 1x and 2x. macOS only ever reports these two in
    /// practice, but any oddball value degrades gracefully to the nearer one.
    private static func normalizedScale(_ backingScale: CGFloat) -> CGFloat {
        backingScale > 1.5 ? 2 : 1
    }

    /// A small seamless tile; Core Graphics pattern fill repeats it across the
    /// screen, so a huge display costs the same memory as this one tile.
    /// `.legacy` presets always render at the original fixed 256×256 px /
    /// 128×128 pt size, ignoring `backingScale`. `.spectral` presets render a
    /// 256×256 pt tile whose backing pixel size follows `backingScale`.
    static func tile(
        for preset: TexturePreset,
        adjustments: GrainAdjustments = .none,
        backingScale: CGFloat = 2,
        cached: Bool = true
    ) -> NSImage {
        let scale = normalizedScale(backingScale)
        let key = "\(preset.cacheSignature)|\(adjustments.tileCacheKey)|bs\(scale)"
        if cached, let hit = tileCache.get(key) {
            cacheMetrics.tileHits += 1
            return hit
        }
        if cached { cacheMetrics.tileMisses += 1 }

        let image: NSImage
        switch preset.engineVersion {
        case .legacy:
            image = legacyTile(preset: preset, adjustments: adjustments, cached: cached)
        case .spectral, .spectralPlus:
            image = spectralTile(preset: preset, adjustments: adjustments, scale: scale, cached: cached)
        }

        if cached { tileCache.set(key, image) }
        return image
    }

    /// The overlay tile: grain composited over the preset's tint wash, so a
    /// single pattern image carries the whole texture. Used as a CALayer
    /// pattern background — see TextureView for why. Rendered eagerly into a
    /// full-resolution bitmap (not a lazily-drawn NSImage) so retina displays
    /// get a sharp pattern at the view's actual backing scale.
    static func compositeTile(
        for preset: TexturePreset,
        adjustments: GrainAdjustments = .none,
        backingScale: CGFloat = 2
    ) -> NSImage {
        let scale = normalizedScale(backingScale)
        let key = "\(preset.cacheSignature)|\(adjustments.cacheKey)|bs\(scale)"
        if let hit = compositeCache.get(key) {
            cacheMetrics.compositeHits += 1
            return hit
        }
        cacheMetrics.compositeMisses += 1

        let grain = tile(for: preset, adjustments: adjustments, backingScale: scale)
        let pointSize = grain.size
        let pixelWidth = max(1, Int((pointSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((pointSize.height * scale).rounded()))

        guard
            let grainImage = grain.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return grain
        }

        if let tintColor = preset.tint.usingColorSpace(.sRGB) {
            let matte = CGFloat(min(max(adjustments.matte, 0), 1))
            let red = tintColor.redComponent * (1 - matte) + 0.5 * matte
            let green = tintColor.greenComponent * (1 - matte) + 0.5 * matte
            let blue = tintColor.blueComponent * (1 - matte) + 0.5 * matte
            context.setFillColor(
                red: red,
                green: green,
                blue: blue,
                alpha: min(1, preset.tintAlpha + 0.18 * matte)
            )
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        context.draw(grainImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        let image = context.makeImage().map { NSImage(cgImage: $0, size: pointSize) } ?? grain
        compositeCache.set(key, image)
        return image
    }

    /// Swatch used in the menu texture picker: the texture drawn over a plain
    /// background, boosted so it is recognizable at thumbnail size. Rendered
    /// eagerly into a full-resolution bitmap sized for `backingScale`.
    static func preview(
        for preset: TexturePreset,
        size: CGSize,
        backingScale: CGFloat = 2,
        cached: Bool = true
    ) -> NSImage {
        let scale = normalizedScale(backingScale)
        let sizeKey = "\(Double(size.width).bitPattern)x\(Double(size.height).bitPattern)"
        let key = "\(preset.cacheSignature)|\(sizeKey)|bs\(scale)"
        if cached, let hit = previewCache.get(key) {
            cacheMetrics.previewHits += 1
            return hit
        }
        if cached { cacheMetrics.previewMisses += 1 }

        let grain = tile(for: preset, backingScale: scale, cached: cached)
        let pixelWidth = max(1, Int((size.width * scale).rounded()))
        let pixelHeight = max(1, Int((size.height * scale).rounded()))
        let backdrop: NSColor = preset.isDark
            ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            : .white

        guard
            let grainImage = grain.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let backdropColor = backdrop.usingColorSpace(.sRGB)
        else {
            return NSImage(size: size)
        }

        context.setFillColor(
            red: backdropColor.redComponent,
            green: backdropColor.greenComponent,
            blue: backdropColor.blueComponent,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        if let tintColor = preset.tint.usingColorSpace(.sRGB) {
            context.setFillColor(
                red: tintColor.redComponent,
                green: tintColor.greenComponent,
                blue: tintColor.blueComponent,
                alpha: min(0.9, preset.tintAlpha * 1.7)
            )
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }

        // Tile the seamless grain pattern across the swatch by hand — a raw
        // CGContext has no AppKit pattern-color fill, and the tile is small
        // enough that a manual draw loop is cheap.
        let tileWidth = grainImage.width
        let tileHeight = grainImage.height
        if tileWidth > 0, tileHeight > 0 {
            var y = 0
            while y < pixelHeight {
                var x = 0
                while x < pixelWidth {
                    context.draw(grainImage, in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
                    x += tileWidth
                }
                y += tileHeight
            }
        }

        guard let composed = context.makeImage() else { return NSImage(size: size) }
        let image = NSImage(cgImage: composed, size: size)
        if cached { previewCache.set(key, image) }
        return image
    }

    // MARK: - Field (shared cache across both engines)

    /// Returns the deterministic [0, 1] noise/spectrum field driving a
    /// preset's grain, generating it if the cache doesn't already have it.
    /// Keyed by `grainSignature` (structure/engine/seed) plus grain scale
    /// and, for the spectral engine only, backing scale — the field's shape
    /// changes with all three; legacy ignores backing scale entirely (it
    /// always renders at the fixed 256px size), so its key omits it and
    /// every scale shares one cached field. Never keyed by color or
    /// strength, so edits to those reuse the same field.
    private static func field(for preset: TexturePreset, adjustments: GrainAdjustments, scale: CGFloat, cached: Bool) -> [Float] {
        let backingFactor = max(1, Int(scale.rounded()))
        let key: String
        switch preset.engineVersion {
        case .legacy:
            key = "\(preset.grainSignature)|\(adjustments.fieldCacheKey)"
        case .spectral, .spectralPlus:
            key = "\(preset.grainSignature)|\(adjustments.fieldCacheKey)|bs\(backingFactor)"
        }
        if cached, let hit = fieldCache.get(key) {
            cacheMetrics.fieldHits += 1
            return hit
        }
        if cached { cacheMetrics.fieldMisses += 1 }

        let value: [Float]
        switch preset.engineVersion {
        case .legacy:
            value = legacyFractalNoise(size: fieldSize, preset: preset, adjustments: adjustments)
        case .spectral:
            value = spectralField(size: fieldSize * backingFactor, backingFactor: backingFactor, preset: preset, adjustments: adjustments)
        case .spectralPlus:
            value = v3SpectralField(size: fieldSize * backingFactor, backingFactor: backingFactor, preset: preset, adjustments: adjustments)
        }

        if cached { fieldCache.set(key, value) }
        return value
    }

    // MARK: - Legacy engine (byte-for-byte original generator)

    /// Renders the original 256×256 px / 128×128 pt tile exactly as the very
    /// first generator did. `backingScale` is intentionally not consulted —
    /// version-less saved/exported custom papers must keep decoding to
    /// `.legacy` and rendering pixel-identical output forever.
    private static func legacyTile(preset: TexturePreset, adjustments: GrainAdjustments, cached: Bool) -> NSImage {
        let pixelSize = fieldSize
        let noise = field(for: preset, adjustments: adjustments, scale: 1, cached: cached)

        guard
            let dark = preset.darkColor.usingColorSpace(.sRGB),
            let light = preset.lightColor.usingColorSpace(.sRGB)
        else {
            return NSImage(size: NSSize(width: pixelSize / 2, height: pixelSize / 2))
        }
        let darkR = dark.redComponent, darkG = dark.greenComponent, darkB = dark.blueComponent
        let lightR = light.redComponent, lightG = light.greenComponent, lightB = light.blueComponent
        let darkStrength = min(1, preset.darkStrength * Float(adjustments.strength))
        let lightStrength = min(1, preset.lightStrength * Float(adjustments.strength))

        var pixels = [UInt8](repeating: 0, count: pixelSize * pixelSize * 4)
        for i in 0..<(pixelSize * pixelSize) {
            let delta = noise[i] - 0.5
            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
            let alpha: Float
            if delta < 0 {
                r = darkR; g = darkG; b = darkB
                alpha = min(1, -delta * 2) * darkStrength
            } else {
                r = lightR; g = lightG; b = lightB
                alpha = min(1, delta * 2) * lightStrength
            }
            // Premultiplied RGBA
            let a = CGFloat(alpha)
            pixels[i * 4 + 0] = UInt8(r * a * 255)
            pixels[i * 4 + 1] = UInt8(g * a * 255)
            pixels[i * 4 + 2] = UInt8(b * a * 255)
            pixels[i * 4 + 3] = UInt8(a * 255)
        }

        let image = pixels.withUnsafeMutableBytes { buffer -> NSImage? in
            guard
                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: pixelSize,
                    height: pixelSize,
                    bitsPerComponent: 8,
                    bytesPerRow: pixelSize * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                let cgImage = context.makeImage()
            else {
                return nil
            }
            // Report the tile at half its pixel size so grain stays fine on
            // Retina displays (2 device pixels per point).
            return NSImage(cgImage: cgImage, size: NSSize(width: pixelSize / 2, height: pixelSize / 2))
        }
        return image ?? NSImage(size: NSSize(width: pixelSize / 2, height: pixelSize / 2))
    }

    /// Sums the preset's octaves of tileable value noise (plus optional weave
    /// modulation) into a [0, 1] field. Untouched since the original engine —
    /// this is the function the legacy SHA-256 fixture pins down.
    private static func legacyFractalNoise(
        size: Int,
        preset: TexturePreset,
        adjustments: GrainAdjustments
    ) -> [Float] {
        var rng = SplitMix64(seed: stableSeed(preset.id))
        var out = [Float](repeating: 0, count: size * size)
        let totalWeight = preset.octaves.reduce(Float(0)) { $0 + $1.weight }

        for octave in preset.octaves {
            // Snap scaled cells to powers of two: only divisors of the tile
            // size wrap cleanly, anything else would show a seam.
            let scaled = Double(octave.cell) * adjustments.scale
            let cell = 1 << max(0, min(6, Int(log2(max(1, scaled)).rounded())))
            let layer = valueNoise(size: size, cell: cell, rng: &rng)
            let w = octave.weight / totalWeight
            for i in 0..<out.count {
                out[i] += layer[i] * w
            }
        }

        if let weave = preset.weave {
            // Whole cycles across the tile, or the weave itself would seam.
            let period = Double(weave.period) * adjustments.scale
            let cycles = max(1, (Double(size) / period).rounded())
            let k = 2 * Float.pi * Float(cycles) / Float(size)
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

    // MARK: - Spectral engine (v2)

    /// Renders a 256×256 pt tile whose backing pixel size follows `scale`
    /// (256 px at 1x, 512 px at 2x). The field is synthesized directly at
    /// that backing-pixel resolution (see `spectralField`), so every device
    /// pixel gets its own independently synthesized sample — there is no
    /// upsampling or block replication here.
    private static func spectralTile(
        preset: TexturePreset,
        adjustments: GrainAdjustments,
        scale: CGFloat,
        cached: Bool
    ) -> NSImage {
        let logical = fieldSize
        let factor = max(1, Int(scale.rounded()))
        let pixelSize = logical * factor
        let noise = field(for: preset, adjustments: adjustments, scale: scale, cached: cached)

        guard
            let dark = preset.darkColor.usingColorSpace(.sRGB),
            let light = preset.lightColor.usingColorSpace(.sRGB)
        else {
            return NSImage(size: NSSize(width: logical, height: logical))
        }
        let darkR = dark.redComponent, darkG = dark.greenComponent, darkB = dark.blueComponent
        let lightR = light.redComponent, lightG = light.greenComponent, lightB = light.blueComponent
        let darkStrength = min(1, preset.darkStrength * Float(adjustments.strength))
        let lightStrength = min(1, preset.lightStrength * Float(adjustments.strength))

        var pixels = [UInt8](repeating: 0, count: pixelSize * pixelSize * 4)
        for py in 0..<pixelSize {
            for px in 0..<pixelSize {
                let delta = noise[py * pixelSize + px] - 0.5
                let r: CGFloat
                let g: CGFloat
                let b: CGFloat
                let alpha: Float
                if delta < 0 {
                    r = darkR; g = darkG; b = darkB
                    alpha = min(1, -delta * 2) * darkStrength
                } else {
                    r = lightR; g = lightG; b = lightB
                    alpha = min(1, delta * 2) * lightStrength
                }
                let a = CGFloat(alpha)
                let o = (py * pixelSize + px) * 4
                pixels[o + 0] = UInt8(r * a * 255)
                pixels[o + 1] = UInt8(g * a * 255)
                pixels[o + 2] = UInt8(b * a * 255)
                pixels[o + 3] = UInt8(a * 255)
            }
        }

        let image = pixels.withUnsafeMutableBytes { buffer -> NSImage? in
            guard
                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: pixelSize,
                    height: pixelSize,
                    bitsPerComponent: 8,
                    bytesPerRow: pixelSize * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                let cgImage = context.makeImage()
            else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: logical, height: logical))
        }
        return image ?? NSImage(size: NSSize(width: logical, height: logical))
    }

    /// Synthesizes the v2 grain field directly at `size` × `size` samples —
    /// `size` is the backing-pixel resolution (256 at 1x, 512 at 2x; see
    /// `spectralTile`), not a fixed logical size upsampled afterward, so
    /// Retina tiles are a genuine higher-resolution synthesis rather than a
    /// replicated 2×2 block per logical sample. `backingFactor` (1 or 2,
    /// i.e. `size / 256`) scales every octave cell size, weave period, and
    /// fiber dimension below, so the field's *logical* (256×256 pt)
    /// structure — the same cell sizes, weave cycles, and fiber lengths
    /// relative to the tile — stays identical across backing scales; only
    /// the sampling density changes.
    ///
    /// Builds a random-phase frequency spectrum with exact Hermitian
    /// (conjugate) symmetry: every off-axis bin's mirror partner
    /// `((n - u) % n, (n - v) % n)` is set to its exact complex conjugate,
    /// and the four bins that are their own mirror (DC and, since `n` is
    /// always even, the three Nyquist bins) are constructed with zero
    /// imaginary part — so the inverse FFT is guaranteed real by
    /// construction, with no imaginary component ever discarded. The
    /// result is inverse-transformed via `vDSP_fft2d_zip` (whose inverse
    /// transform is not itself normalized) and divided by `n * n`, then
    /// empirically normalized into a signed field, and layered with a
    /// deterministic weave, toroidally wrapped fiber splats, and sparse
    /// flecks.
    ///
    /// `preset.octaves` drive the spectrum's radial energy profile (coarser
    /// cells concentrate energy at lower spatial frequencies); `preset.weave`
    /// drives both the crosshatch and, when present, the fiber splats; the
    /// coarsest octave's weight drives the flecks. Everything is seeded from
    /// `preset.seed`, so the same seed always reproduces the same field
    /// regardless of the preset's id, color, or strength.
    private static func spectralField(
        size: Int,
        backingFactor: Int,
        preset: TexturePreset,
        adjustments: GrainAdjustments
    ) -> [Float] {
        let n = size
        let log2n = vDSP_Length(log2(Double(n)))
        var rng = SplitMix64(seed: preset.seed)
        let factor = Double(backingFactor)

        let totalWeight = preset.octaves.reduce(Float(0)) { $0 + $1.weight }
        let safeTotalWeight = totalWeight > 0 ? totalWeight : 1
        // Each octave contributes a Gaussian bump of spectral energy centered
        // on the cycle count its cell size implies — a coarser cell (bigger
        // `cell`) sits at a lower characteristic frequency, mirroring how the
        // legacy engine's grid resolution scaled with cell size. Cell size is
        // scaled by `backingFactor` (in addition to the grain-scale
        // adjustment) so the characteristic frequency, expressed in cycles
        // per logical 256pt tile, is identical at every backing scale.
        let bands: [(k0: Float, sigma: Float, weight: Float)] = preset.octaves.map { octave in
            let cell = max(1.0, Double(octave.cell) * adjustments.scale * factor)
            let k0 = Float(min(Double(n) / 2, Double(n) / (2 * cell)))
            let sigma = max(1, k0 * 0.6)
            return (k0, sigma, octave.weight / safeTotalWeight)
        }

        func amplitude(_ u: Int, _ v: Int) -> Float {
            let fv = Float(min(v, n - v))
            let fu = Float(min(u, n - u))
            let r = (fu * fu + fv * fv).squareRoot()
            var power: Float = 0
            for band in bands {
                let d = (r - band.k0) / band.sigma
                power += band.weight * exp(-0.5 * d * d)
            }
            return power > 0 ? power.squareRoot() : 0
        }

        var realp = [Float](repeating: 0, count: n * n)
        var imagp = [Float](repeating: 0, count: n * n)

        // Draws a random amplitude/phase coefficient at (u, v).
        func assignRandom(_ u: Int, _ v: Int) {
            let amp = amplitude(u, v)
            let phase = rng.unitFloat() * 2 * Float.pi
            let idx = v * n + u
            realp[idx] = amp * cos(phase)
            imagp[idx] = amp * sin(phase)
        }

        // Sets (u, v)'s conjugate mirror partner ((n - u) % n, (n - v) % n)
        // from its already-assigned coefficient.
        func mirrorConjugate(_ u: Int, _ v: Int) {
            let idx = v * n + u
            let midx = ((n - v) % n) * n + (n - u) % n
            realp[midx] = realp[idx]
            imagp[midx] = -imagp[idx]
        }

        // A bin that is its own mirror partner (DC and, since n is always
        // even here, the three Nyquist bins) must be purely real, or the
        // spectrum isn't Hermitian and the inverse transform isn't real.
        func assignSelfConjugate(_ u: Int, _ v: Int) {
            let amp = amplitude(u, v)
            let sign: Float = rng.unitFloat() < 0.5 ? -1 : 1
            let idx = v * n + u
            realp[idx] = amp * sign
            imagp[idx] = 0
        }

        let half = n / 2

        // DC is left at zero rather than drawn from the band profile — an
        // unbounded low-frequency band could otherwise inject a large
        // constant offset that dwarfs the rest of the spectrum for very
        // coarse, heavily scaled-up octaves. (realp/imagp already zeroed.)

        // Row v = 0: (u, 0)'s mirror partner is (n - u, 0), also in row 0.
        for u in 1..<half {
            assignRandom(u, 0)
            mirrorConjugate(u, 0)
        }
        assignSelfConjugate(half, 0)

        // Row v = half (the Nyquist row): same within-row self-mirroring.
        for u in 1..<half {
            assignRandom(u, half)
            mirrorConjugate(u, half)
        }
        assignSelfConjugate(0, half)
        assignSelfConjugate(half, half)

        // Rows v = 1..<half are free; each row's conjugate partner is the
        // entire row (n - v), which is never independently drawn.
        for v in 1..<half {
            for u in 0..<n {
                assignRandom(u, v)
            }
            for u in 0..<n {
                mirrorConjugate(u, v)
            }
        }

        var base = realp
        if let setup = fftSetup(log2n: log2n) {
            let transformed = realp.withUnsafeMutableBufferPointer { rp -> Bool in
                imagp.withUnsafeMutableBufferPointer { ip -> Bool in
                    guard let realAddress = rp.baseAddress, let imagAddress = ip.baseAddress else { return false }
                    var split = DSPSplitComplex(realp: realAddress, imagp: imagAddress)
                    // Row-major layout (index = v * n + u): consecutive u
                    // (dimension 0) are contiguous, so its stride is 1;
                    // consecutive v (dimension 1) advance a whole row, so
                    // its stride is n.
                    vDSP_fft2d_zip(setup, &split, 1, vDSP_Stride(n), log2n, log2n, FFTDirection(FFT_INVERSE))
                    return true
                }
            }
            if transformed {
                // vDSP_fft2d_zip's inverse transform is not normalized —
                // undo its implicit ×(n·n) gain before the field's values
                // are meaningful.
                var divisor = Float(n * n)
                vDSP_vsdiv(realp, 1, &divisor, &realp, 1, vDSP_Length(realp.count))
                base = realp
            }
        }

        // Empirical signed-field normalization: center on the field's actual
        // mean, then scale by its actual peak deviation, so the visible
        // contrast stays consistent regardless of how the octave weights
        // happened to distribute spectral energy.
        var mean: Float = 0
        vDSP_meanv(base, 1, &mean, vDSP_Length(base.count))
        var negativeMean = -mean
        vDSP_vsadd(base, 1, &negativeMean, &base, 1, vDSP_Length(base.count))
        var maxDeviation: Float = 0
        vDSP_maxmgv(base, 1, &maxDeviation, vDSP_Length(base.count))
        if maxDeviation > 0 {
            var divisor = maxDeviation
            vDSP_vsdiv(base, 1, &divisor, &base, 1, vDSP_Length(base.count))
        }
        for i in 0..<base.count {
            base[i] = base[i] * 0.5 + 0.5
        }

        if let weave = preset.weave {
            // Deterministic weave: whole cycles across the tile, or the
            // crosshatch itself would seam. The period is scaled by
            // `backingFactor` alongside `n`, so the cycle count — and thus
            // the weave's appearance relative to the logical tile — is
            // identical at every backing scale.
            let period = max(1.0, Double(weave.period) * adjustments.scale * factor)
            let cycles = max(1, (Double(n) / period).rounded())
            let k = 2 * Float.pi * Float(cycles) / Float(n)
            for y in 0..<n {
                let sy = sin(Float(y) * k)
                for x in 0..<n {
                    let sx = sin(Float(x) * k)
                    let i = y * n + x
                    base[i] = min(1, max(0, base[i] + (sx + sy) * 0.5 * weave.amplitude))
                }
            }
            stampFibers(
                into: &base,
                size: n,
                amplitude: weave.amplitude,
                scale: Float(adjustments.scale),
                pixelScale: Float(backingFactor),
                rng: &rng
            )
        }

        if let coarse = preset.octaves.max(by: { $0.cell < $1.cell }), coarse.cell > 1 {
            stampFlecks(
                into: &base,
                size: n,
                weight: coarse.weight / safeTotalWeight,
                pixelScale: Float(backingFactor),
                rng: &rng
            )
        }

        return base
    }

    // MARK: - Spectral+ engine (v3)

    /// Builds on the v2 spectral field by layering three physically
    /// motivated passes:
    ///
    /// 1. **V2 spectral base** — the same Hermitian-symmetric random-phase
    ///    spectrum that drives every v2 preset. This gives the field its
    ///    broadband paper-grain texture.
    /// 2. **Oriented fiber modulation** — a set of Gabor-like sinusoidal
    ///    carriers aligned along `v3Config.fiberAngle`. Each carrier is
    ///    amplitude-modulated by a slowly varying Gaussian envelope so the
    ///    fibers appear as discrete strands rather than a uniform stripe.
    ///    `fiberStrength` scales the modulation depth. Fibers darken the
    ///    field (never brighten it) — real paper fibers scatter and absorb
    ///    light — which is what gives v3 its glare-reduction advantage over
    ///    v2 at identical intensity.
    /// 3. **Perlin surface roughness** — an independent multi-octave
    ///    value-noise layer whose amplitude is controlled by
    ///    `surfaceRoughness`. This fills in the micro-texture between
    ///    fibers, simulating the pulp irregularities of real handmade
    ///    paper.
    ///
    /// All three layers are synthesized at the target backing-pixel
    /// resolution (`size × size`) so Retina tiles get genuine detail,
    /// and the result is deterministically seeded from `preset.seed`.
    private static func v3SpectralField(
        size: Int,
        backingFactor: Int,
        preset: TexturePreset,
        adjustments: GrainAdjustments
    ) -> [Float] {
        let n = size
        let config = preset.v3Config ?? .default

        // 1. V2 spectral base
        var base = spectralField(
            size: size,
            backingFactor: backingFactor,
            preset: preset,
            adjustments: adjustments
        )

        // 2. Oriented fiber modulation
        let fiberStrength = max(0, min(1, config.fiberStrength))
        if fiberStrength > 0.001 {
            var fiberRng = SplitMix64(seed: preset.seed &+ 0xA5B9_C4E3_D2F1_0678)
            let angle = config.fiberAngle
            // Number of fiber bundles scales with strength.
            let bundleCount = max(1, Int((fiberStrength * 12).rounded()))
            let factor = Float(backingFactor)
            let nf = Float(n)

            for _ in 0..<bundleCount {
                // Each bundle has a random origin, a small angular jitter,
                // and a Gaussian envelope that confines its visibility to
                // a narrow stripe.
                let cx = fiberRng.unitFloat() * nf
                let cy = fiberRng.unitFloat() * nf
                let jitter = (fiberRng.unitFloat() - 0.5) * 0.3
                let bCos = cos(angle + jitter)
                let bSin = sin(angle + jitter)
                // Envelope sigma perpendicular to the fiber direction,
                // in pixels. Tighter stripes at lower strength.
                let envelopeSigma = (3.0 + fiberRng.unitFloat() * 6.0) * max(0.25, Float(adjustments.scale)) * factor
                // Carrier frequency along the fiber direction: one full
                // cycle every `carrierPeriod` pixels.
                let carrierPeriod = max(4.0, (8.0 + fiberRng.unitFloat() * 20.0) * max(0.25, Float(adjustments.scale)) * factor)
                let carrierK = 2 * Float.pi / carrierPeriod
                // Per-bundle intensity. Fibers are darkening: real paper
                // fibers scatter and absorb light, so the carrier is
                // mapped to a 0…1 envelope that darkens (never brightens)
                // the field along the strand — this is what makes v3
                // actually cut glare instead of only adding texture.
                let amplitude = fiberStrength * (0.25 + fiberRng.unitFloat() * 0.30)
                let twoSigmaSq = 2 * envelopeSigma * envelopeSigma

                // Stamp this bundle across the tile.
                let radius = Int((envelopeSigma * 3).rounded())
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        // Rotate into fiber-local coordinates.
                        let fdx = Float(dx) * bCos + Float(dy) * bSin
                        let fdy = -Float(dx) * bSin + Float(dy) * bCos
                        // Gaussian envelope perpendicular to fiber.
                        let env = exp(-fdy * fdy / twoSigmaSq)
                        guard env > 0.01 else { continue }
                        // Asymmetric darkening: carrier is biased to
                        // 0…1 (mean ½) so a fiber reads as a soft,
                        // shadowed strand rather than an equal
                        // bright/dark fringe pair.
                        let strand = (sin(fdx * carrierK) + 1) * 0.5
                        let sx = ((Int(cx) + dx) % n + n) % n
                        let sy = ((Int(cy) + dy) % n + n) % n
                        let idx = sy * n + sx
                        base[idx] = max(0, base[idx] - amplitude * env * strand)
                    }
                }
            }
        }

        // 3. Perlin surface roughness
        let roughness = max(0, min(1, config.surfaceRoughness))
        if roughness > 0.001 {
            let surface = perlinSurfaceNoise(
                size: n,
                seed: preset.seed &+ 0x7E3D_A1B8_C9F0_5246,
                scale: adjustments.scale,
                backingFactor: backingFactor
            )
            for i in 0..<base.count {
                // Roughness is a paper-to-screen veil, not a light source:
                // retain only the non-positive half of the signed field so
                // v3 can never brighten a pixel relative to v2.
                let darkening = min(0, surface[i]) * roughness * 0.35
                base[i] = max(0, base[i] + darkening)
            }
        }

        return base
    }

    /// Multi-octave tileable Perlin-style value noise for surface
    /// roughness. Uses Hermite interpolation (smootherstep) on a
    /// coarse random grid, toroidally wrapped so the result tiles
    /// seamlessly. Four octaves at ratios 1:½:¼:⅛ give a good
    /// balance between broad undulation and fine grain.
    private static func perlinSurfaceNoise(
        size: Int,
        seed: UInt64,
        scale: Double,
        backingFactor: Int
    ) -> [Float] {
        let scaleF = max(0.25, Float(scale))
        var rng = SplitMix64(seed: seed)
        var out = [Float](repeating: 0, count: size * size)
        let factor = max(1, Int(backingFactor))
        let octaves: [(cell: Int, weight: Float)] = [
            (max(1, Int((4 * scaleF * Float(factor)).rounded())), 0.40),
            (max(1, Int((8 * scaleF * Float(factor)).rounded())), 0.30),
            (max(1, Int((16 * scaleF * Float(factor)).rounded())), 0.20),
            (max(1, Int((32 * scaleF * Float(factor)).rounded())), 0.10),
        ]
        let totalWeight = octaves.reduce(Float(0)) { $0 + $1.weight }
        for octave in octaves {
            let cell = octave.cell
            let g = max(1, size / cell)
            var grid = [Float](repeating: 0, count: g * g)
            for i in 0..<grid.count { grid[i] = rng.unitFloat() * 2 - 1 }
            let w = octave.weight / totalWeight
            for y in 0..<size {
                let fy = Float(y) / Float(cell)
                let y0 = Int(fy) % g
                let y1 = (y0 + 1) % g
                let ty = fy - Float(Int(fy))
                let sy = ty * ty * (3 - 2 * ty)
                for x in 0..<size {
                    let fx = Float(x) / Float(cell)
                    let x0 = Int(fx) % g
                    let x1 = (x0 + 1) % g
                    let tx = fx - Float(Int(fx))
                    let sx = tx * tx * (3 - 2 * tx)
                    let a = grid[y0 * g + x0]
                    let b = grid[y0 * g + x1]
                    let c = grid[y1 * g + x0]
                    let d = grid[y1 * g + x1]
                    let top = a + (b - a) * sx
                    let bottom = c + (d - c) * sx
                    out[y * size + x] += (top + (bottom - top) * sy) * w
                }
            }
        }
        return out
    }

    /// Lazily created, permanently retained FFT setups, keyed by size — the
    /// field is always 256×256 or 512×512 (log2n 8 or 9), so this never
    /// grows past two entries.
    private static var fftSetups: [vDSP_Length: FFTSetup] = [:]

    private static func fftSetup(log2n: vDSP_Length) -> FFTSetup? {
        if let cached = fftSetups[log2n] { return cached }
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        fftSetups[log2n] = setup
        return setup
    }

    /// Scatters deterministic, toroidally wrapped elongated fiber splats
    /// across the field, standing in for the visible fiber strands of real
    /// paper. Count and intensity are driven by the weave's amplitude, so
    /// papers with no weave (or a faint one) show few or no fibers.
    /// `pixelScale` (the backing-scale factor: 1 or 2) scales fiber length
    /// and splat radius/sigma so a fiber occupies the same physical extent
    /// of the tile regardless of backing scale.
    private static func stampFibers(
        into field: inout [Float],
        size: Int,
        amplitude: Float,
        scale: Float,
        pixelScale: Float,
        rng: inout SplitMix64
    ) {
        guard amplitude > 0.001 else { return }
        let count = min(48, max(0, Int((amplitude * 32).rounded())))
        guard count > 0 else { return }
        let n = Float(size)
        for _ in 0..<count {
            let cx = rng.unitFloat() * n
            let cy = rng.unitFloat() * n
            let angle = rng.unitFloat() * 2 * Float.pi
            let length = (24 + rng.unitFloat() * 40) * max(0.25, scale) * pixelScale
            let sign: Float = rng.unitFloat() < 0.5 ? -1 : 1
            let intensity = sign * amplitude * (0.35 + rng.unitFloat() * 0.55)
            let dx = cos(angle)
            let dy = sin(angle)
            let steps = max(4, Int(length / 0.75))
            for step in 0...steps {
                let t = Float(step) / Float(steps)
                let distance = (t - 0.5) * length
                let px = cx + dx * distance
                let py = cy + dy * distance
                // Fade in/out along the fiber's length instead of stopping
                // abruptly at its ends.
                let taper = sin(Float.pi * t)
                splat(
                    into: &field,
                    size: size,
                    x: px,
                    y: py,
                    radius: max(1, Int((2 * pixelScale).rounded())),
                    sigma: 1.1 * pixelScale,
                    intensity: intensity * taper
                )
            }
        }
    }

    /// Scatters deterministic, toroidally wrapped sparse flecks — tiny
    /// bright/dark inclusions like the mottling in real handmade paper.
    /// Count and intensity are driven by the coarsest octave's weight.
    /// `pixelScale` scales splat radius/sigma so a fleck occupies the same
    /// physical extent of the tile regardless of backing scale.
    private static func stampFlecks(
        into field: inout [Float],
        size: Int,
        weight: Float,
        pixelScale: Float,
        rng: inout SplitMix64
    ) {
        guard weight > 0.001 else { return }
        let count = min(120, max(0, Int((weight * 90).rounded())))
        guard count > 0 else { return }
        let n = Float(size)
        for _ in 0..<count {
            let px = rng.unitFloat() * n
            let py = rng.unitFloat() * n
            let sign: Float = rng.unitFloat() < 0.5 ? -1 : 1
            let intensity = sign * weight * (0.5 + rng.unitFloat() * 0.8)
            splat(
                into: &field,
                size: size,
                x: px,
                y: py,
                radius: max(1, Int((1 * pixelScale).rounded())),
                sigma: 0.7 * pixelScale,
                intensity: intensity
            )
        }
    }

    /// Adds a small Gaussian-falloff bump centered at a fractional (x, y),
    /// wrapping toroidally at the field's edges so splats near one edge
    /// continue seamlessly from the opposite one.
    private static func splat(
        into field: inout [Float],
        size: Int,
        x: Float,
        y: Float,
        radius: Int,
        sigma: Float,
        intensity: Float
    ) {
        guard intensity != 0 else { return }
        let ix = Int(x.rounded(.down))
        let iy = Int(y.rounded(.down))
        let twoSigmaSquared = 2 * sigma * sigma
        for dy in -radius...radius {
            let wy = Float(dy) - (y - Float(iy))
            for dx in -radius...radius {
                let wx = Float(dx) - (x - Float(ix))
                let distanceSquared = wx * wx + wy * wy
                let weight = exp(-distanceSquared / twoSigmaSquared)
                guard weight > 0.01 else { continue }
                let sx = ((ix + dx) % size + size) % size
                let sy = ((iy + dy) % size + size) % size
                let index = sy * size + sx
                field[index] = min(1, max(0, field[index] + intensity * weight))
            }
        }
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

/// A tiny bounded LRU cache. Not thread-safe by design — every caller in this
/// file runs on the main thread (menu UI, overlay windows), matching how the
/// renderer has always been used.
private struct LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var storage: [Key: Value] = [:]
    /// Least-recently-used first.
    private var order: [Key] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func get(_ key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    mutating func set(_ key: Key, _ value: Value) {
        if storage[key] == nil {
            order.append(key)
        } else {
            touch(key)
        }
        storage[key] = value
        evictIfNeeded()
    }

    mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private mutating func evictIfNeeded() {
        while storage.count > capacity, !order.isEmpty {
            let oldest = order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }
}
