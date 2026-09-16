import AppKit

/// A paper texture preset. Each preset is defined by a translucent tint wash
/// plus procedural grain parameters (octaves of tileable value noise, and an
/// optional woven "fabric" modulation).
///
/// The overlay is rendered at full design strength; the user-facing intensity
/// slider simply drives the overlay window's alphaValue.

/// Which procedural engine renders a preset's grain. `.legacy` preserves the
/// original per-pixel value-noise generator byte-for-byte so version-less
/// saved/exported custom papers keep rendering exactly as they always have;
/// `.spectral` is retained for v2 custom papers and compatibility fixtures;
/// `.spectralPlus` is the current engine used by built-ins and new papers.
enum TextureEngineVersion: Int, Codable {
    case legacy = 1
    case spectral = 2
    /// Advanced spectral+ engine: oriented fiber bundles, Gabor-modulated
    /// grain, and Perlin surface roughness layered over the v2 spectrum.
    case spectralPlus = 3
}

/// Parameters specific to the v3 (spectral+) engine. Carried alongside
/// every preset so cache keys and the renderer can reach them without
/// side-channel lookup. The values are intentionally a flat struct —
/// no nesting, no optionals — so cache-key hashing stays trivial.
struct TextureEngineConfig: Equatable {
    /// Dominant fiber orientation in radians (0 = horizontal, π/2 = vertical).
    var fiberAngle: Float = 0.3
    /// How strongly oriented fibers modulate the grain field, 0…1.
    var fiberStrength: Float = 0.30
    /// Perlin surface roughness mixed into the field, 0…1.
    var surfaceRoughness: Float = 0.15

    static let `default` = TextureEngineConfig()

    /// Cache-key fragment covering every render-relevant v3 parameter.
    /// Uses exact Float bit patterns: the renderer consumes full-precision
    /// values, so decimal rounding (e.g. %.3f) would let sub-0.001 changes
    /// collide on one cache entry and produce stale tiles.
    var cacheKey: String {
        "v3|fa\(fiberAngle.bitPattern)|fs\(fiberStrength.bitPattern)|sr\(surfaceRoughness.bitPattern)"
    }
}

struct TexturePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String

    /// Base tint wash laid under the grain.
    let tint: NSColor
    /// Opacity of the tint wash at full design strength (0-1).
    let tintAlpha: CGFloat

    /// Color used for grain pixels darker than the midpoint.
    let darkColor: NSColor
    /// Color used for grain pixels lighter than the midpoint.
    let lightColor: NSColor
    /// How strongly dark grain speckles show (0-1).
    let darkStrength: Float
    /// How strongly light grain speckles show (0-1).
    let lightStrength: Float

    /// Noise octaves as (cellSizeInPixels, weight). Cell size 1 is per-pixel
    /// white noise; larger cells give coarser blotches.
    let octaves: [(cell: Int, weight: Float)]

    /// Optional woven crosshatch: (periodInPixels, amplitude).
    let weave: (period: Int, amplitude: Float)?

    /// Dark presets are grouped separately and previewed on a dark backdrop.
    let isDark: Bool

    /// Procedural engine used to render this preset's grain.
    let engineVersion: TextureEngineVersion
    /// Per-preset RNG seed feeding the grain field.
    let seed: UInt64

    /// v3 engine configuration. `nil` for legacy/spectral presets.
    let v3Config: TextureEngineConfig?

    init(
        id: String,
        name: String,
        subtitle: String,
        tint: NSColor,
        tintAlpha: CGFloat,
        darkColor: NSColor,
        lightColor: NSColor,
        darkStrength: Float,
        lightStrength: Float,
        octaves: [(cell: Int, weight: Float)],
        weave: (period: Int, amplitude: Float)?,
        isDark: Bool,
        engineVersion: TextureEngineVersion = .spectralPlus,
        seed: UInt64 = 0,
        v3Config: TextureEngineConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.tint = tint
        self.tintAlpha = tintAlpha
        self.darkColor = darkColor
        self.lightColor = lightColor
        self.darkStrength = darkStrength
        self.lightStrength = lightStrength
        self.octaves = octaves
        self.weave = weave
        self.isDark = isDark
        self.engineVersion = engineVersion
        self.seed = seed
        self.v3Config = engineVersion == .spectralPlus
            ? (v3Config ?? .default)
            : v3Config
    }

    /// Creates a v2 variant of a preset without changing its identity,
    /// colors, grain structure, or seed. Used for compatibility comparisons.
    init(v2 base: TexturePreset) {
        self.init(
            id: base.id,
            name: base.name,
            subtitle: base.subtitle,
            tint: base.tint,
            tintAlpha: base.tintAlpha,
            darkColor: base.darkColor,
            lightColor: base.lightColor,
            darkStrength: base.darkStrength,
            lightStrength: base.lightStrength,
            octaves: base.octaves,
            weave: base.weave,
            isDark: base.isDark,
            engineVersion: .spectral,
            seed: base.seed,
            v3Config: nil
        )
    }

    /// Creates a v3 (spectral+) variant of an existing v2 preset by
    /// replacing its engine version and attaching v3 config while
    /// preserving every other field (tint, octaves, seed, …).
    init(v2 base: TexturePreset, v3Config: TextureEngineConfig) {
        self.init(
            id: base.id,
            name: base.name,
            subtitle: base.subtitle,
            tint: base.tint,
            tintAlpha: base.tintAlpha,
            darkColor: base.darkColor,
            lightColor: base.lightColor,
            darkStrength: base.darkStrength,
            lightStrength: base.lightStrength,
            octaves: base.octaves,
            weave: base.weave,
            isDark: base.isDark,
            engineVersion: .spectralPlus,
            seed: base.seed,
            v3Config: v3Config
        )
    }

    static func == (lhs: TexturePreset, rhs: TexturePreset) -> Bool {
        lhs.cacheSignature == rhs.cacheSignature
    }

    /// Cache key covering only the deterministic field-structure inputs —
    /// octaves, weave, engine version, and seed. The expensive noise/spectrum
    /// computation depends on nothing else, so the renderer can share a
    /// generated field across presets (or edits) that only differ in color.
    var grainSignature: String {
        var signature = "v\(engineVersion.rawValue)|seed\(seed)"
        signature += "|" + octaves.map { "\($0.cell):\($0.weight.bitPattern)" }.joined(separator: ",")
        if let weave { signature += "|w\(weave.period):\(weave.amplitude.bitPattern)" }
        if let config = v3Config { signature += "|\(config.cacheKey)" }
        return signature
    }

    /// Cache key that changes when any render-relevant parameter changes.
    /// Built-ins are immutable so this is effectively their id; custom papers
    /// reuse their id across edits, so parameters must participate.
    var cacheSignature: String {
        func bits(_ value: CGFloat) -> UInt64 {
            Double(value).bitPattern
        }

        var signature = "\(id)|ta\(bits(tintAlpha))|ds\(darkStrength.bitPattern)|ls\(lightStrength.bitPattern)"
        if let tint = tint.usingColorSpace(.sRGB) {
            signature += "|t\(bits(tint.redComponent)),\(bits(tint.greenComponent)),\(bits(tint.blueComponent))"
        }
        if let dark = darkColor.usingColorSpace(.sRGB) {
            signature += "|d\(bits(dark.redComponent)),\(bits(dark.greenComponent)),\(bits(dark.blueComponent))"
        }
        if let light = lightColor.usingColorSpace(.sRGB) {
            signature += "|l\(bits(light.redComponent)),\(bits(light.greenComponent)),\(bits(light.blueComponent))"
        }
        signature += "|" + grainSignature
        return signature
    }

    static func preset(id: String) -> TexturePreset {
        all.first { $0.id == id } ?? all[0]
    }

    static var light: [TexturePreset] { all.filter { !$0.isDark } }
    static var dark: [TexturePreset] { all.filter { $0.isDark } }

    /// Low-pattern alternatives for text-heavy work. These are visual design
    /// choices, not clinical eye-strain treatments. Keep their IDs stable.
    static let readingCollection: [TexturePreset] = [
        TexturePreset(
            id: "clear-veil", name: "Clear Veil",
            subtitle: "Neutral dimming, no grain",
            tint: NSColor(srgbRed: 0.35, green: 0.35, blue: 0.35, alpha: 1),
            tintAlpha: 0.16,
            darkColor: .black, lightColor: .white,
            darkStrength: 0, lightStrength: 0,
            octaves: [(1, 1)], weave: nil, isDark: false,
            seed: 0x434C454152,
            v3Config: TextureEngineConfig(fiberAngle: 0, fiberStrength: 0, surfaceRoughness: 0)
        ),
        TexturePreset(
            id: "book-cream", name: "Book Cream",
            subtitle: "Faint warmth, barely-there grain",
            tint: NSColor(srgbRed: 0.60, green: 0.50, blue: 0.35, alpha: 1),
            tintAlpha: 0.20,
            darkColor: NSColor(srgbRed: 0.25, green: 0.22, blue: 0.17, alpha: 1),
            lightColor: NSColor(srgbRed: 0.80, green: 0.77, blue: 0.70, alpha: 1),
            darkStrength: 0.035, lightStrength: 0.005,
            octaves: [(1, 0.85), (2, 0.15)], weave: nil, isDark: false,
            seed: 0x424F4F4B,
            v3Config: TextureEngineConfig(fiberAngle: 0.2, fiberStrength: 0.015, surfaceRoughness: 0.01)
        ),
        TexturePreset(
            id: "quiet-gray", name: "Quiet Gray",
            subtitle: "Balanced gray, fine quiet grain",
            tint: NSColor(srgbRed: 0.30, green: 0.31, blue: 0.32, alpha: 1),
            tintAlpha: 0.22,
            darkColor: NSColor(srgbRed: 0.15, green: 0.16, blue: 0.17, alpha: 1),
            lightColor: NSColor(srgbRed: 0.65, green: 0.66, blue: 0.67, alpha: 1),
            darkStrength: 0.025, lightStrength: 0.003,
            octaves: [(1, 0.9), (2, 0.1)], weave: nil, isDark: false,
            seed: 0x47524159,
            v3Config: TextureEngineConfig(fiberAngle: 0, fiberStrength: 0.01, surfaceRoughness: 0.005)
        ),
        TexturePreset(
            id: "evening-shade", name: "Evening Shade",
            subtitle: "Deeper dimming, minimal texture",
            tint: NSColor(srgbRed: 0.08, green: 0.07, blue: 0.06, alpha: 1),
            tintAlpha: 0.40,
            darkColor: .black,
            lightColor: NSColor(srgbRed: 0.25, green: 0.23, blue: 0.21, alpha: 1),
            darkStrength: 0.015, lightStrength: 0.002,
            octaves: [(1, 1)], weave: nil, isDark: true,
            seed: 0x4556454E494E47,
            v3Config: TextureEngineConfig(fiberAngle: 0, fiberStrength: 0.005, surfaceRoughness: 0.005)
        )
    ]

    var isQuietReading: Bool { Self.readingCollection.contains { $0.id == id } }

    static let all: [TexturePreset] = readingCollection + [
        // MARK: Light papers
        TexturePreset(
            id: "classic-matte",
            name: "Soft Wove",
            subtitle: "Smooth, even-milled finish",
            tint: NSColor(srgbRed: 0.98, green: 0.96, blue: 0.92, alpha: 1),
            tintAlpha: 0.35,
            darkColor: NSColor(srgbRed: 0.25, green: 0.22, blue: 0.18, alpha: 1),
            lightColor: .white,
            darkStrength: 0.50,
            lightStrength: 0.35,
            octaves: [(1, 0.50), (2, 0.30), (4, 0.20)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "rice-paper",
            name: "Rice Paper",
            subtitle: "Feather-light, near invisible",
            tint: NSColor(srgbRed: 0.98, green: 0.97, blue: 0.94, alpha: 1),
            tintAlpha: 0.40,
            darkColor: NSColor(srgbRed: 0.40, green: 0.38, blue: 0.32, alpha: 1),
            lightColor: .white,
            darkStrength: 0.30,
            lightStrength: 0.50,
            octaves: [(1, 0.30), (4, 0.40), (8, 0.30)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "whisper-weave",
            name: "Laid Cotton",
            subtitle: "Fine ribbed cotton sheet",
            tint: NSColor(srgbRed: 0.97, green: 0.95, blue: 0.93, alpha: 1),
            tintAlpha: 0.32,
            darkColor: NSColor(srgbRed: 0.28, green: 0.25, blue: 0.22, alpha: 1),
            lightColor: .white,
            darkStrength: 0.45,
            lightStrength: 0.40,
            octaves: [(1, 0.40), (2, 0.35), (4, 0.25)],
            weave: (period: 8, amplitude: 0.12),
            isDark: false
        ),
        TexturePreset(
            id: "newsprint",
            name: "Newsprint",
            subtitle: "Cool gray daily-paper stock",
            tint: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.92, alpha: 1),
            tintAlpha: 0.38,
            darkColor: NSColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1),
            lightColor: .white,
            darkStrength: 0.50,
            lightStrength: 0.30,
            octaves: [(1, 0.55), (2, 0.30), (4, 0.15)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "painters-press",
            name: "Cold Press",
            subtitle: "Rough watercolor stock",
            tint: NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1),
            tintAlpha: 0.35,
            darkColor: NSColor(srgbRed: 0.30, green: 0.28, blue: 0.25, alpha: 1),
            lightColor: .white,
            darkStrength: 0.55,
            lightStrength: 0.40,
            octaves: [(1, 0.30), (2, 0.25), (4, 0.20), (16, 0.25)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "artist-canvas",
            name: "Artist Canvas",
            subtitle: "Coarse stretched weave",
            tint: NSColor(srgbRed: 0.94, green: 0.91, blue: 0.84, alpha: 1),
            tintAlpha: 0.40,
            darkColor: NSColor(srgbRed: 0.32, green: 0.28, blue: 0.22, alpha: 1),
            lightColor: NSColor(srgbRed: 1.0, green: 0.98, blue: 0.93, alpha: 1),
            darkStrength: 0.50,
            lightStrength: 0.40,
            octaves: [(1, 0.30), (2, 0.30), (4, 0.40)],
            weave: (period: 10, amplitude: 0.28),
            isDark: false
        ),
        // MARK: Warm tones
        TexturePreset(
            id: "sunbaked-parchment",
            name: "Foxed Amber",
            subtitle: "Age-warmed amber grain",
            tint: NSColor(srgbRed: 0.93, green: 0.82, blue: 0.60, alpha: 1),
            tintAlpha: 0.48,
            darkColor: NSColor(srgbRed: 0.36, green: 0.26, blue: 0.10, alpha: 1),
            lightColor: NSColor(srgbRed: 1.0, green: 0.95, blue: 0.82, alpha: 1),
            darkStrength: 0.50,
            lightStrength: 0.30,
            octaves: [(1, 0.35), (2, 0.25), (4, 0.20), (16, 0.20)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "saddle-linen",
            name: "Bookcloth",
            subtitle: "Binder's linen weave",
            tint: NSColor(srgbRed: 0.88, green: 0.80, blue: 0.68, alpha: 1),
            tintAlpha: 0.45,
            darkColor: NSColor(srgbRed: 0.30, green: 0.24, blue: 0.16, alpha: 1),
            lightColor: NSColor(srgbRed: 0.99, green: 0.96, blue: 0.90, alpha: 1),
            darkStrength: 0.50,
            lightStrength: 0.35,
            octaves: [(1, 0.35), (2, 0.35), (4, 0.30)],
            weave: (period: 6, amplitude: 0.20),
            isDark: false
        ),
        TexturePreset(
            id: "recycled-kraft",
            name: "Recycled Kraft",
            subtitle: "Rough brown packing stock",
            tint: NSColor(srgbRed: 0.76, green: 0.62, blue: 0.45, alpha: 1),
            tintAlpha: 0.50,
            darkColor: NSColor(srgbRed: 0.30, green: 0.22, blue: 0.12, alpha: 1),
            lightColor: NSColor(srgbRed: 0.95, green: 0.88, blue: 0.75, alpha: 1),
            darkStrength: 0.55,
            lightStrength: 0.30,
            octaves: [(1, 0.30), (2, 0.20), (4, 0.20), (16, 0.30)],
            weave: nil,
            isDark: false
        ),
        // MARK: Tinted
        TexturePreset(
            id: "mulberry-veil",
            name: "Plum Kozo",
            subtitle: "Plum-washed kozo fibre",
            tint: NSColor(srgbRed: 0.85, green: 0.78, blue: 0.86, alpha: 1),
            tintAlpha: 0.42,
            darkColor: NSColor(srgbRed: 0.30, green: 0.20, blue: 0.30, alpha: 1),
            lightColor: NSColor(srgbRed: 0.98, green: 0.95, blue: 1.0, alpha: 1),
            darkStrength: 0.45,
            lightStrength: 0.35,
            octaves: [(1, 0.45), (2, 0.30), (4, 0.25)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "rose-quartz",
            name: "Rose Quartz",
            subtitle: "Soft blush wash",
            tint: NSColor(srgbRed: 0.93, green: 0.83, blue: 0.84, alpha: 1),
            tintAlpha: 0.45,
            darkColor: NSColor(srgbRed: 0.35, green: 0.22, blue: 0.24, alpha: 1),
            lightColor: NSColor(srgbRed: 1.0, green: 0.96, blue: 0.96, alpha: 1),
            darkStrength: 0.40,
            lightStrength: 0.35,
            octaves: [(1, 0.45), (2, 0.30), (4, 0.25)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "sage-press",
            name: "Sage Press",
            subtitle: "Muted botanical green",
            tint: NSColor(srgbRed: 0.80, green: 0.86, blue: 0.76, alpha: 1),
            tintAlpha: 0.45,
            darkColor: NSColor(srgbRed: 0.22, green: 0.30, blue: 0.20, alpha: 1),
            lightColor: NSColor(srgbRed: 0.95, green: 1.0, blue: 0.92, alpha: 1),
            darkStrength: 0.45,
            lightStrength: 0.30,
            octaves: [(1, 0.40), (2, 0.30), (4, 0.30)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "nordic-sky",
            name: "Nordic Sky",
            subtitle: "Cool pale blue",
            tint: NSColor(srgbRed: 0.80, green: 0.87, blue: 0.93, alpha: 1),
            tintAlpha: 0.45,
            darkColor: NSColor(srgbRed: 0.18, green: 0.26, blue: 0.34, alpha: 1),
            lightColor: NSColor(srgbRed: 0.94, green: 0.98, blue: 1.0, alpha: 1),
            darkStrength: 0.40,
            lightStrength: 0.35,
            octaves: [(1, 0.45), (2, 0.30), (4, 0.25)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "vellum-mist",
            name: "Frost Glassine",
            subtitle: "Translucent frosted haze",
            tint: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
            tintAlpha: 0.50,
            darkColor: NSColor(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1),
            lightColor: .white,
            darkStrength: 0.25,
            lightStrength: 0.60,
            octaves: [(1, 0.40), (2, 0.30), (8, 0.30)],
            weave: nil,
            isDark: false
        ),
        TexturePreset(
            id: "monastic-felt",
            name: "Felt Side",
            subtitle: "The sheet's soft felt side",
            tint: NSColor(srgbRed: 0.85, green: 0.86, blue: 0.82, alpha: 1),
            tintAlpha: 0.45,
            darkColor: NSColor(srgbRed: 0.28, green: 0.30, blue: 0.26, alpha: 1),
            lightColor: NSColor(srgbRed: 0.97, green: 0.98, blue: 0.95, alpha: 1),
            darkStrength: 0.45,
            lightStrength: 0.35,
            octaves: [(2, 0.30), (4, 0.40), (8, 0.30)],
            weave: nil,
            isDark: false
        ),
        // MARK: Dark
        TexturePreset(
            id: "carbon-ledger",
            name: "Ink Stone",
            subtitle: "Ground-ink black",
            tint: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1),
            tintAlpha: 0.38,
            darkColor: NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1),
            lightColor: NSColor(srgbRed: 0.80, green: 0.80, blue: 0.85, alpha: 1),
            darkStrength: 0.30,
            lightStrength: 0.45,
            octaves: [(1, 0.45), (2, 0.30), (4, 0.25)],
            weave: nil,
            isDark: true
        ),
        TexturePreset(
            id: "midnight-slate",
            name: "Midnight Slate",
            subtitle: "Blue-black stone",
            tint: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1),
            tintAlpha: 0.40,
            darkColor: NSColor(srgbRed: 0.01, green: 0.02, blue: 0.04, alpha: 1),
            lightColor: NSColor(srgbRed: 0.65, green: 0.72, blue: 0.85, alpha: 1),
            darkStrength: 0.30,
            lightStrength: 0.40,
            octaves: [(1, 0.40), (2, 0.30), (8, 0.30)],
            weave: nil,
            isDark: true
        ),
        TexturePreset(
            id: "espresso",
            name: "Espresso",
            subtitle: "Warm near-black roast",
            tint: NSColor(srgbRed: 0.14, green: 0.10, blue: 0.08, alpha: 1),
            tintAlpha: 0.40,
            darkColor: NSColor(srgbRed: 0.03, green: 0.02, blue: 0.01, alpha: 1),
            lightColor: NSColor(srgbRed: 0.85, green: 0.75, blue: 0.65, alpha: 1),
            darkStrength: 0.30,
            lightStrength: 0.40,
            octaves: [(1, 0.40), (2, 0.30), (4, 0.30)],
            weave: nil,
            isDark: true
        ),
        // MARK: Spectral+ (v3) — oriented fiber, surface roughness
        TexturePreset(
            id: "gesso-ground",
            name: "Gesso Ground",
            subtitle: "Sized artist's ground, matte fiber veil",
            tint: NSColor(srgbRed: 0.86, green: 0.84, blue: 0.79, alpha: 1),
            tintAlpha: 0.48,
            darkColor: NSColor(srgbRed: 0.38, green: 0.35, blue: 0.30, alpha: 1),
            lightColor: NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1),
            darkStrength: 0.45,
            lightStrength: 0.25,
            octaves: [(1, 0.35), (2, 0.35), (4, 0.30)],
            weave: nil,
            isDark: false,
            engineVersion: .spectralPlus,
            seed: 0x9E3779B97F4A7C15,
            v3Config: TextureEngineConfig(fiberAngle: 0.9, fiberStrength: 0.45, surfaceRoughness: 0.20)
        ),
        TexturePreset(
            id: "linen-veil",
            name: "Linen Veil",
            subtitle: "Cool blue-gray with woven fiber alignment",
            tint: NSColor(srgbRed: 0.80, green: 0.83, blue: 0.86, alpha: 1),
            tintAlpha: 0.50,
            darkColor: NSColor(srgbRed: 0.32, green: 0.36, blue: 0.42, alpha: 1),
            lightColor: NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1),
            darkStrength: 0.40,
            lightStrength: 0.20,
            octaves: [(1, 0.30), (2, 0.30), (4, 0.40)],
            weave: nil,
            isDark: false,
            engineVersion: .spectralPlus,
            seed: 0xBF58476D1CE4E5B9,
            v3Config: TextureEngineConfig(fiberAngle: 1.57, fiberStrength: 0.50, surfaceRoughness: 0.15)
        ),
        TexturePreset(
            id: "parchment-grain",
            name: "Parchment Grain",
            subtitle: "Warm parchment with coarse tooth",
            tint: NSColor(srgbRed: 0.84, green: 0.74, blue: 0.58, alpha: 1),
            tintAlpha: 0.52,
            darkColor: NSColor(srgbRed: 0.40, green: 0.32, blue: 0.20, alpha: 1),
            lightColor: NSColor(srgbRed: 0.96, green: 0.91, blue: 0.80, alpha: 1),
            darkStrength: 0.50,
            lightStrength: 0.20,
            octaves: [(1, 0.30), (2, 0.25), (4, 0.25), (16, 0.20)],
            weave: nil,
            isDark: false,
            engineVersion: .spectralPlus,
            seed: 0x94D049BB133111EB,
            v3Config: TextureEngineConfig(fiberAngle: 0.35, fiberStrength: 0.35, surfaceRoughness: 0.35)
        ),
        TexturePreset(
            id: "slate-veil",
            name: "Slate Veil",
            subtitle: "Deep slate with visible fiber strands",
            tint: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
            tintAlpha: 0.45,
            darkColor: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
            lightColor: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.68, alpha: 1),
            darkStrength: 0.35,
            lightStrength: 0.30,
            octaves: [(1, 0.40), (2, 0.30), (4, 0.30)],
            weave: nil,
            isDark: true,
            engineVersion: .spectralPlus,
            seed: 0xA5B9C4E3D2F10678,
            v3Config: TextureEngineConfig(fiberAngle: 1.1, fiberStrength: 0.40, surfaceRoughness: 0.25)
        ),
    ]
}
