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
        weave: (period: Int, amplitude: Float)? = (32, 0.15)
    ) -> TexturePreset {
        TexturePreset(
            id: id,
            name: "Test Paper",
            subtitle: "",
            tint: NSColor(srgbRed: 0.9, green: 0.9, blue: 0.85, alpha: 1),
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
        XCTAssertEqual(paper.engineVersion, .spectral, "freshly created papers must default to the v2 engine")

        let data = try JSONEncoder().encode(paper)
        let decoded = try JSONDecoder().decode(CustomPaper.self, from: data)

        XCTAssertEqual(decoded, paper)
        XCTAssertEqual(decoded.engineVersion, paper.engineVersion)
        XCTAssertEqual(decoded.seed, paper.seed, "a stored seed must round-trip exactly, not be regenerated")
    }

    // MARK: - Built-in engine-version contract

    func testBuiltInClassicMatteIsSpectral() {
        let preset = TexturePreset.preset(id: "classic-matte")
        XCTAssertEqual(
            preset.engineVersion, .spectral,
            "every built-in preset renders through the v2 spectral engine; only version-less decoded CustomPaper stays on legacy"
        )
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
}
