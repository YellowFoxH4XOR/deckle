import XCTest
import AppKit
import CoreGraphics
import CryptoKit
@testable import Deckle

/// Behavior tests for the v1/v2 engine split introduced across
/// `TexturePreset`, `CustomPaper`, and `TextureRenderer`: engine-version
/// defaulting/decoding, byte-for-byte legacy fidelity, v2 determinism and
/// sizing, and the renderer's bounded, diagnosable caches.
final class TextureRendererTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TextureRenderer.resetCaches()
    }

    override func tearDown() {
        TextureRenderer.resetCaches()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Raw RGBA8 bytes straight off the tile's backing `CGImage`, with no
    /// resampling — the same bytes the renderer wrote into its `CGContext`.
    private func rawPixelBytes(_ image: NSImage, file: StaticString = #filePath, line: UInt = #line) -> Data {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data = cgImage.dataProvider?.data
        else {
            XCTFail("expected a backing CGImage with pixel data", file: file, line: line)
            return Data()
        }
        return data as Data
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// djb2 hash, matching both `TextureRenderer.stableSeed(_:)` and
    /// `CustomPaper.legacySeed(from:)` — every id-derived seed in the engine
    /// uses this exact algorithm.
    private func djb2(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }

    private func spectralPreset(
        id: String,
        seed: UInt64,
        octaves: [(cell: Int, weight: Float)] = [(1, 0.6), (4, 0.4)],
        weave: (period: Int, amplitude: Float)? = (32, 0.15),
        tint: NSColor = NSColor(srgbRed: 0.9, green: 0.9, blue: 0.85, alpha: 1)
    ) -> TexturePreset {
        TexturePreset(
            id: id,
            name: "Test Paper",
            subtitle: "",
            tint: tint,
            tintAlpha: 0.3,
            darkColor: NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1),
            lightColor: .white,
            darkStrength: 0.5,
            lightStrength: 0.4,
            octaves: octaves,
            weave: weave,
            isDark: false,
            engineVersion: .spectral,
            seed: seed
        )
    }

    // MARK: - CustomPaper engine-version / seed contract

    func testMissingVersionCustomPaperDecodesLegacy() throws {
        // No "engineVersion" and no "seed" key at all — the shape of a
        // paper exported before either field existed.
        let json = """
        {
            "id": "imported-paper",
            "name": "Imported",
            "tintRed": 0.9,
            "tintGreen": 0.85,
            "tintBlue": 0.8,
            "wash": 0.3,
            "weave": 0.1,
            "blotch": 0.2
        }
        """.data(using: .utf8)!

        let paper = try JSONDecoder().decode(CustomPaper.self, from: json)

        XCTAssertEqual(paper.engineVersion, .legacy)
        XCTAssertEqual(paper.seed, djb2("imported-paper"), "seed-less imports must derive a seed deterministically from id")
    }

    func testNewCustomPaperIsSpectralAndRoundTripsVersionAndSeed() throws {
        let paper = CustomPaper()
        XCTAssertEqual(paper.engineVersion, .spectralPlus, "freshly created papers must default to the v3 spectral+ engine")

        let data = try JSONEncoder().encode(paper)
        let decoded = try JSONDecoder().decode(CustomPaper.self, from: data)

        XCTAssertEqual(decoded, paper)
        XCTAssertEqual(decoded.engineVersion, paper.engineVersion)
        XCTAssertEqual(decoded.seed, paper.seed, "a stored seed must round-trip exactly, not be regenerated")
    }

    // MARK: - Built-in engine-version contract

    func testBuiltInClassicMatteUsesSpectralPlus() {
        let preset = TexturePreset.preset(id: "classic-matte")
        XCTAssertEqual(
            preset.engineVersion, .spectralPlus,
            "built-in presets use the v3 spectral+ engine; stored v2 and legacy CustomPaper values remain compatible"
        )
        XCTAssertNotNil(preset.v3Config)
    }

    func testEveryBuiltInUsesSpectralPlus() {
        XCTAssertTrue(TexturePreset.all.allSatisfy { $0.engineVersion == .spectralPlus })
    }

    // MARK: - Legacy (v1) byte fidelity

    func testVersionLessCustomPaperRendersThroughLegacyWithPinnedHash() throws {
        // No "engineVersion" and no "seed" key at all — the shape of a
        // paper exported before either field existed. Decoding must keep it
        // on the legacy engine forever, byte-for-byte.
        let json = """
        {
            "id": "imported-paper",
            "name": "Imported",
            "tintRed": 0.9,
            "tintGreen": 0.85,
            "tintBlue": 0.8,
            "wash": 0.3,
            "weave": 0.1,
            "blotch": 0.2
        }
        """.data(using: .utf8)!

        let paper = try JSONDecoder().decode(CustomPaper.self, from: json)
        let preset = TexturePreset(custom: paper)

        XCTAssertEqual(
            preset.engineVersion, .legacy,
            "a version-less decoded CustomPaper must keep rendering through the legacy engine"
        )

        let tile = TextureRenderer.tile(for: preset)

        XCTAssertEqual(
            sha256Hex(rawPixelBytes(tile)),
            "8a4f8f31f581315f7e85e950105b78b1a9feecaa669aa5d44a5eeff7e70cb4bd",
            "legacy-rendered version-less custom paper pixels must stay byte-identical to the original generator"
        )
    }

    // MARK: - Spectral (v2) determinism

    func testSpectralSameSeedProducesIdenticalBytesDistinctSeedDiffers() {
        let presetA = spectralPreset(id: "seed-a", seed: 42)
        let presetB = spectralPreset(id: "seed-b", seed: 42)
        let presetC = spectralPreset(id: "seed-c", seed: 99)

        let bytesA = rawPixelBytes(TextureRenderer.tile(for: presetA, cached: false))
        let bytesB = rawPixelBytes(TextureRenderer.tile(for: presetB, cached: false))
        let bytesC = rawPixelBytes(TextureRenderer.tile(for: presetC, cached: false))

        XCTAssertEqual(bytesA, bytesB, "same seed, different id: grain must render byte-identical")
        XCTAssertNotEqual(bytesA, bytesC, "distinct seeds must render distinct grain")
    }

    // MARK: - Spectral (v2) sizing

    func testSpectralTileIs256PointsWith256PxAt1xAnd512PxAt2x() {
        let preset = spectralPreset(id: "sizing", seed: 7)

        let tile1x = TextureRenderer.tile(for: preset, backingScale: 1, cached: false)
        XCTAssertEqual(tile1x.size, NSSize(width: 256, height: 256))
        guard let cg1x = tile1x.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("expected a backing CGImage at 1x")
        }
        XCTAssertEqual(cg1x.width, 256)
        XCTAssertEqual(cg1x.height, 256)

        let tile2x = TextureRenderer.tile(for: preset, backingScale: 2, cached: false)
        XCTAssertEqual(tile2x.size, NSSize(width: 256, height: 256), "logical tile size must stay 256pt regardless of backing scale")
        guard let cg2x = tile2x.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return XCTFail("expected a backing CGImage at 2x")
        }
        XCTAssertEqual(cg2x.width, 512)
        XCTAssertEqual(cg2x.height, 512)
    }

    func testSpectralTileAt2xIsNotNearestNeighborReplicationOf1x() {
        let preset = spectralPreset(id: "no-nearest-neighbor-check", seed: 11)

        guard
            let cg1x = TextureRenderer.tile(for: preset, backingScale: 1, cached: false)
                .cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data1x = cg1x.dataProvider?.data
        else {
            return XCTFail("expected a backing CGImage at 1x")
        }
        guard
            let cg2x = TextureRenderer.tile(for: preset, backingScale: 2, cached: false)
                .cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data2x = cg2x.dataProvider?.data
        else {
            return XCTFail("expected a backing CGImage at 2x")
        }

        let bytes1x = [UInt8](data1x as Data)
        let bytes2x = [UInt8](data2x as Data)
        let stride1x = cg1x.bytesPerRow
        let stride2x = cg2x.bytesPerRow

        // A naive nearest-neighbor 2x upsample would repeat every 1x pixel
        // across its corresponding 2x2 block, so the (2x, 2y) pixel of the
        // 2x raster would always equal the (x, y) pixel of the 1x raster.
        // The v2 engine instead resynthesizes the field at the target
        // resolution, so this correspondence must break down somewhere.
        func pixel(_ bytes: [UInt8], stride: Int, x: Int, y: Int) -> ArraySlice<UInt8> {
            let offset = y * stride + x * 4
            return bytes[offset..<offset + 4]
        }

        var foundMismatch = false
        outer: for y in 0..<cg1x.height {
            for x in 0..<cg1x.width {
                if pixel(bytes1x, stride: stride1x, x: x, y: y)
                    != pixel(bytes2x, stride: stride2x, x: x * 2, y: y * 2)
                {
                    foundMismatch = true
                    break outer
                }
            }
        }

        XCTAssertTrue(
            foundMismatch,
            "a 2x spectral raster that were merely a nearest-neighbor upsample of the 1x field would match it at every even coordinate"
        )
    }

    // MARK: - Cache diagnostics

    func testUncachedPreviewLeavesCacheMetricsUnchanged() {
        // Warm every cache first so "unchanged" is a meaningful assertion
        // rather than comparing all-zero to all-zero.
        let warm = spectralPreset(id: "warm", seed: 1)
        _ = TextureRenderer.tile(for: warm)
        _ = TextureRenderer.preview(for: warm, size: CGSize(width: 64, height: 64))

        let before = TextureRenderer.cacheMetrics
        let preset = spectralPreset(id: "uncached-preview", seed: 2)

        _ = TextureRenderer.preview(for: preset, size: CGSize(width: 64, height: 64), cached: false)

        XCTAssertEqual(TextureRenderer.cacheMetrics, before, "cached:false must bypass every cache lookup, not just the preview cache")
    }

    func testUncachedPreviewWithCachedGrainSharesTheFieldButNotTheComposite() {
        let preset = spectralPreset(id: "draft-swatch", seed: 3)
        let size = CGSize(width: 64, height: 64)

        let before = TextureRenderer.cacheMetrics
        _ = TextureRenderer.preview(for: preset, size: size, cached: false, cacheGrain: true)
        let afterFirst = TextureRenderer.cacheMetrics

        XCTAssertEqual(afterFirst.previewHits, before.previewHits)
        XCTAssertEqual(afterFirst.previewMisses, before.previewMisses, "the transient swatch must stay out of the preview LRU")
        XCTAssertEqual(afterFirst.tileMisses, before.tileMisses + 1)
        XCTAssertEqual(afterFirst.fieldMisses, before.fieldMisses + 1)

        // Same structure, different tint: the field and tile come back from
        // cache while the composite is still synthesized fresh.
        let recolored = spectralPreset(id: "draft-swatch", seed: 3, tint: NSColor(srgbRed: 0.2, green: 0.6, blue: 0.6, alpha: 1))
        _ = TextureRenderer.preview(for: recolored, size: size, cached: false, cacheGrain: true)
        let afterSecond = TextureRenderer.cacheMetrics

        XCTAssertEqual(afterSecond.previewMisses, afterFirst.previewMisses)
        XCTAssertEqual(afterSecond.fieldHits, afterFirst.fieldHits + 1, "color edits must reuse the spectral field")
        XCTAssertEqual(afterSecond.fieldMisses, afterFirst.fieldMisses)
    }

    func testBoundedCachesRemainWithinCapacityAfterManyDistinctRenders() {
        let count = 40
        let presets = (0..<count).map { spectralPreset(id: "bound-\($0)", seed: UInt64($0)) }

        for preset in presets {
            _ = TextureRenderer.tile(for: preset)
        }

        let beforeFirstReplay = TextureRenderer.cacheMetrics
        _ = TextureRenderer.tile(for: presets[0])
        let afterFirstReplay = TextureRenderer.cacheMetrics

        XCTAssertEqual(
            afterFirstReplay.tileMisses, beforeFirstReplay.tileMisses + 1,
            "the earliest render must have been evicted after \(count) distinct renders, proving the tile cache stays bounded"
        )
        XCTAssertEqual(afterFirstReplay.tileHits, beforeFirstReplay.tileHits)

        let beforeLastReplay = TextureRenderer.cacheMetrics
        _ = TextureRenderer.tile(for: presets[count - 1])
        let afterLastReplay = TextureRenderer.cacheMetrics

        XCTAssertEqual(
            afterLastReplay.tileHits, beforeLastReplay.tileHits + 1,
            "the most recently rendered preset must still be cached"
        )
        XCTAssertEqual(afterLastReplay.tileMisses, beforeLastReplay.tileMisses)
    }

    // MARK: - Spectral+ (v3) engine

    /// v3 preset with a tiny tile so tests are fast.
    private func v3Preset(id: String, seed: UInt64) -> TexturePreset {
        TexturePreset(
            id: id,
            name: "v3 Test",
            subtitle: "",
            tint: NSColor(srgbRed: 0.9, green: 0.88, blue: 0.84, alpha: 1),
            tintAlpha: 0.42,
            darkColor: NSColor(srgbRed: 0.38, green: 0.35, blue: 0.30, alpha: 1),
            lightColor: NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1),
            darkStrength: 0.45,
            lightStrength: 0.25,
            octaves: [(1, 0.35), (2, 0.35), (4, 0.30)],
            weave: nil,
            isDark: false,
            engineVersion: .spectralPlus,
            seed: seed,
            v3Config: TextureEngineConfig(fiberAngle: 0.9, fiberStrength: 0.45, surfaceRoughness: 0.20)
        )
    }

    func testV3SameSeedProducesIdenticalBytes() {
        let a = v3Preset(id: "v3-a", seed: 42)
        let b = v3Preset(id: "v3-b", seed: 42)

        XCTAssertEqual(
            rawPixelBytes(TextureRenderer.tile(for: a, cached: false)),
            rawPixelBytes(TextureRenderer.tile(for: b, cached: false)),
            "same seed must produce byte-identical v3 grain regardless of preset id"
        )
    }

    func testV3DifferentSeedProducesDifferentBytes() {
        let a = v3Preset(id: "v3-a", seed: 42)
        let b = v3Preset(id: "v3-b", seed: 99)

        XCTAssertNotEqual(
            rawPixelBytes(TextureRenderer.tile(for: a, cached: false)),
            rawPixelBytes(TextureRenderer.tile(for: b, cached: false)),
            "different seeds must produce distinct v3 grain"
        )
    }

    func testV3FiberAngleChangesGrain() {
        let horizontal = TexturePreset(v2: v3Preset(id: "v3-h", seed: 7), v3Config: TextureEngineConfig(fiberAngle: 0, fiberStrength: 0.5, surfaceRoughness: 0))
        let vertical = TexturePreset(v2: v3Preset(id: "v3-v", seed: 7), v3Config: TextureEngineConfig(fiberAngle: 1.57, fiberStrength: 0.5, surfaceRoughness: 0))

        XCTAssertNotEqual(
            rawPixelBytes(TextureRenderer.tile(for: horizontal, cached: false)),
            rawPixelBytes(TextureRenderer.tile(for: vertical, cached: false)),
            "fiber angle must change the rendered v3 grain"
        )
    }

    func testV3FieldIsDeterministicAcrossCacheModes() {
        let preset = v3Preset(id: "v3-cache", seed: 5)

        let uncached = TextureRenderer.tile(for: preset, cached: false)
        let cached = TextureRenderer.tile(for: preset, cached: true)

        XCTAssertEqual(
            rawPixelBytes(uncached),
            rawPixelBytes(cached),
            "cached and uncached v3 renders must be identical"
        )
    }

    func testV3CacheKeyDistinguishesSubMilliParameterChanges() {
        // The cache key must use lossless Float bits — decimal rounding
        // would let sub-0.001 slider changes collide on one entry.
        let a = v3Preset(id: "v3-fine", seed: 9)
        let b = TexturePreset(
            v2: a,
            v3Config: TextureEngineConfig(
                fiberAngle: a.v3Config!.fiberAngle + 0.0001,
                fiberStrength: a.v3Config!.fiberStrength,
                surfaceRoughness: a.v3Config!.surfaceRoughness
            )
        )
        XCTAssertNotEqual(a.cacheSignature, b.cacheSignature, "cache signatures must differ for sub-0.001 parameter changes")

        let bytesA = rawPixelBytes(TextureRenderer.tile(for: a, cached: false))
        let bytesB = rawPixelBytes(TextureRenderer.tile(for: b, cached: false))
        XCTAssertNotEqual(bytesA, bytesB, "sub-0.001 parameter changes must render distinct tiles")
    }

    func testAdjustmentCacheKeyDistinguishesSubCentChanges() {
        let preset = v3Preset(id: "adjustment-cache", seed: 17)
        let first = TextureRenderer.GrainAdjustments(scale: 1.001, strength: 1.001)
        let second = TextureRenderer.GrainAdjustments(scale: 1.001, strength: 1.004)

        XCTAssertNotEqual(first.cacheKey, second.cacheKey)
        let firstBytes = rawPixelBytes(TextureRenderer.tile(for: preset, adjustments: first))
        let before = TextureRenderer.cacheMetrics
        let secondBytes = rawPixelBytes(TextureRenderer.tile(for: preset, adjustments: second))
        let after = TextureRenderer.cacheMetrics

        XCTAssertEqual(after.tileMisses, before.tileMisses + 1, "distinct adjustment values must not reuse a tile cache entry")
        XCTAssertEqual(after.fieldMisses, before.fieldMisses, "strength changes should reuse the synthesized field")
        XCTAssertNotEqual(firstBytes, secondBytes, "sub-cent adjustment changes must affect rendered pixels")
    }

    func testMatteChangesOnlyTheCompositeAndZeroIsStable() {
        let preset = v3Preset(id: "matte-cache", seed: 31)
        let base = TextureRenderer.GrainAdjustments.none
        let matte = TextureRenderer.GrainAdjustments(scale: 1, strength: 1, matte: 0.6)

        let zeroBytes = rawPixelBytes(TextureRenderer.compositeTile(for: preset, adjustments: base, backingScale: 1))
        let beforeMatte = TextureRenderer.cacheMetrics
        let matteBytes = rawPixelBytes(TextureRenderer.compositeTile(for: preset, adjustments: matte, backingScale: 1))
        let afterMatte = TextureRenderer.cacheMetrics

        XCTAssertNotEqual(zeroBytes, matteBytes, "matte must change the final composited tile")
        XCTAssertEqual(afterMatte.fieldMisses, beforeMatte.fieldMisses, "matte must not regenerate the grain field")
        XCTAssertEqual(afterMatte.tileMisses, beforeMatte.tileMisses, "matte must reuse the grain tile")

        TextureRenderer.resetCaches()
        let zeroAgain = rawPixelBytes(TextureRenderer.compositeTile(for: preset, adjustments: .init(matte: 0), backingScale: 1))
        XCTAssertEqual(zeroBytes, zeroAgain, "zero matte must preserve the unmatte composited output")
    }

    func testColorAndStrengthCacheKeysAreLossless() {
        let base = v3Preset(id: "numeric-cache", seed: 23)
        let strengthChanged = TexturePreset(
            id: base.id,
            name: base.name,
            subtitle: base.subtitle,
            tint: base.tint,
            tintAlpha: base.tintAlpha,
            darkColor: base.darkColor,
            lightColor: base.lightColor,
            darkStrength: base.darkStrength + 0.0001,
            lightStrength: base.lightStrength,
            octaves: base.octaves,
            weave: base.weave,
            isDark: base.isDark,
            engineVersion: base.engineVersion,
            seed: base.seed,
            v3Config: base.v3Config
        )
        let colorChanged = TexturePreset(
            id: base.id,
            name: base.name,
            subtitle: base.subtitle,
            tint: NSColor(srgbRed: 0.9001, green: 0.9, blue: 0.85, alpha: 1),
            tintAlpha: base.tintAlpha,
            darkColor: base.darkColor,
            lightColor: base.lightColor,
            darkStrength: base.darkStrength,
            lightStrength: base.lightStrength,
            octaves: base.octaves,
            weave: base.weave,
            isDark: base.isDark,
            engineVersion: base.engineVersion,
            seed: base.seed,
            v3Config: base.v3Config
        )

        XCTAssertNotEqual(base.cacheSignature, strengthChanged.cacheSignature)
        XCTAssertNotEqual(base.cacheSignature, colorChanged.cacheSignature)

        _ = TextureRenderer.compositeTile(for: base)
        let beforeStrength = TextureRenderer.cacheMetrics
        _ = TextureRenderer.compositeTile(for: strengthChanged)
        let afterStrength = TextureRenderer.cacheMetrics
        XCTAssertEqual(afterStrength.compositeMisses, beforeStrength.compositeMisses + 1)

        let beforeColor = TextureRenderer.cacheMetrics
        _ = TextureRenderer.compositeTile(for: colorChanged)
        let afterColor = TextureRenderer.cacheMetrics
        XCTAssertEqual(afterColor.compositeMisses, beforeColor.compositeMisses + 1)
    }

    func testV3PresetUsesSpectralPlusEngine() {
        let preset = TexturePreset.preset(id: "gesso-ground")
        XCTAssertEqual(preset.engineVersion, .spectralPlus)
        XCTAssertNotNil(preset.v3Config)
        XCTAssertGreaterThan(preset.v3Config?.fiberStrength ?? 0, 0)
    }

    func testV3BuiltInPresetRenders() {
        for id in ["gesso-ground", "linen-veil", "parchment-grain", "slate-veil"] {
            let preset = TexturePreset.preset(id: id)
            let tile = TextureRenderer.tile(for: preset, cached: false)
            XCTAssertGreaterThan(tile.size.width, 0, "\(id) must render a non-empty tile")
        }
    }

    func testCustomPaperV3RoundTripsFiberParameters() throws {
        let paper = CustomPaper(
            engineVersion: .spectralPlus,
            fiberAngle: 0.7,
            fiberStrength: 0.55,
            surfaceRoughness: 0.30
        )
        let data = try JSONEncoder().encode(paper)
        let decoded = try JSONDecoder().decode(CustomPaper.self, from: data)

        XCTAssertEqual(decoded, paper)
        XCTAssertEqual(decoded.fiberAngle, paper.fiberAngle)
        XCTAssertEqual(decoded.fiberStrength, paper.fiberStrength)
        XCTAssertEqual(decoded.surfaceRoughness, paper.surfaceRoughness)
    }

    func testV2CustomPaperDecodesWithoutFiberParameters() throws {
        // A v2 paper exported before v3 existed must decode with zeroed
        // fiber parameters so it keeps rendering exactly as before.
        let json = """
        {
            "id": "legacy-paper",
            "name": "Legacy",
            "tintRed": 0.9,
            "tintGreen": 0.85,
            "tintBlue": 0.8,
            "wash": 0.3,
            "weave": 0.1,
            "blotch": 0.2,
            "engineVersion": 2,
            "seed": 12345
        }
        """.data(using: .utf8)!

        let paper = try JSONDecoder().decode(CustomPaper.self, from: json)

        XCTAssertEqual(paper.engineVersion, .spectral)
        XCTAssertEqual(paper.fiberAngle, 0)
        XCTAssertEqual(paper.fiberStrength, 0)
        XCTAssertEqual(paper.surfaceRoughness, 0)
    }
}
