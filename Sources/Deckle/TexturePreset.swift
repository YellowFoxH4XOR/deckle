import AppKit

/// A paper texture preset. Each preset is defined by a translucent tint wash
/// plus procedural grain parameters (octaves of tileable value noise, and an
/// optional woven "fabric" modulation).
///
/// The overlay is rendered at full design strength; the user-facing intensity
/// slider simply drives the overlay window's alphaValue.
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

    static func == (lhs: TexturePreset, rhs: TexturePreset) -> Bool {
        lhs.id == rhs.id
    }

    static func preset(id: String) -> TexturePreset {
        all.first { $0.id == id } ?? all[0]
    }

    static var light: [TexturePreset] { all.filter { !$0.isDark } }
    static var dark: [TexturePreset] { all.filter { $0.isDark } }

    static let all: [TexturePreset] = [
        // MARK: Light papers
        TexturePreset(
            id: "classic-matte",
            name: "Classic Matte",
            subtitle: "Smooth, diffused finish",
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
            name: "Whisper Weave",
            subtitle: "Delicate fabric texture",
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
            name: "Painter's Press",
            subtitle: "Cold-press surface",
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
            name: "Sunbaked Parchment",
            subtitle: "Amber-toned grain",
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
            name: "Saddle Linen",
            subtitle: "Natural weave",
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
            name: "Mulberry Veil",
            subtitle: "Plum-toned, translucent",
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
            name: "Vellum Mist",
            subtitle: "Frosted effect",
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
            name: "Monastic Felt",
            subtitle: "Soft, muted wool",
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
            name: "Carbon Ledger",
            subtitle: "Deep graphite",
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
    ]
}
