import XCTest
import AppKit
import CoreGraphics
@testable import Deckle

/// Measures how much each paper actually darkens a pure-white screen.
/// Glare reduction is a luminance change, not the presence of grain.
final class OverlayGlareTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TextureRenderer.resetCaches()
    }

    override func tearDown() {
        TextureRenderer.resetCaches()
        super.tearDown()
    }

    /// Default overlay intensity matches AppState's UserDefaults fallback.
    private let defaultIntensity = 0.22

    // MARK: - v2 engine baseline

    func testEveryBuiltInPaperProducesSomeDimmingOverWhite() {
        for preset in TexturePreset.all {
            let stats = dimmingOverWhite(preset: preset, windowAlpha: defaultIntensity)
            XCTAssertGreaterThan(
                stats.dimming, 0,
                "\(preset.name): composite tile must reduce white luminance at least minimally"
            )
        }
    }

    func testDarkPapersDimMoreThanLightPapersAtSameIntensity() {
        let lightDim = TexturePreset.light.map {
            dimmingOverWhite(preset: $0, windowAlpha: defaultIntensity).dimming
        }
        let darkDim = TexturePreset.dark.map {
            dimmingOverWhite(preset: $0, windowAlpha: defaultIntensity).dimming
        }
        guard let maxLight = lightDim.max(), let minDark = darkDim.min() else {
            return XCTFail("expected at least one light and one dark preset")
        }
        XCTAssertGreaterThan(
            minDark, maxLight,
            "dark papers should dim more than light papers at the same intensity"
        )
    }

    func testWashOnlyModelAgreesThatSoftWoveBarelyDims() {
        let preset = TexturePreset.preset(id: "classic-matte")
        let comfort = washModelDimming(preset: preset, intensity: defaultIntensity)
        // Soft Wove is cream (≈0.98, 0.96, 0.92) at 35% wash × 22% window.
        XCTAssertLessThan(
            comfort,
            0.03,
            "analytic wash model should show Soft Wove cannot dim a white screen"
        )
    }

    func testHigherIntensityProducesMoreDimming() {
        let preset = TexturePreset.preset(id: "classic-matte")
        let low = dimmingOverWhite(preset: preset, windowAlpha: 0.10).dimming
        let high = dimmingOverWhite(preset: preset, windowAlpha: 0.45).dimming
        XCTAssertGreaterThan(high, low, "higher intensity must produce more dimming")
    }

    // MARK: - v3 engine glare reduction

    func testV3VariantDimsMoreThanV2ForSameRecipe() {
        // The v3 engine's darkening fibers must produce more white-screen
        // dimming than the identical v2 recipe at the same intensity — this
        // is the engine's real glare-reduction contribution, independent of
        // the wash × intensity product that caps absolute dimming.
        var regressions: [String] = []
        // Every current built-in is v3; compare it with a synthetic v2
        // version while using the preset's actual stored v3 configuration.
        for preset in TexturePreset.all where preset.engineVersion == .spectralPlus {
            guard let config = preset.v3Config else {
                regressions.append("\(preset.name) has no v3 configuration")
                continue
            }
            let v2 = dimmingOverWhite(preset: TexturePreset(v2: preset), windowAlpha: defaultIntensity).dimming
            let configuredV3 = TexturePreset(v2: preset, v3Config: config)
            let v3 = dimmingOverWhite(preset: configuredV3, windowAlpha: defaultIntensity).dimming
            if v3 < v2 {
                regressions.append(String(format: "%@ v2 %.2f%% → v3 %.2f%%", preset.name, v2 * 100, v3 * 100))
            }
        }
        XCTAssertTrue(
            regressions.isEmpty,
            "v3 must never dim less than v2 for the same recipe: \(regressions.joined(separator: "; "))"
        )
    }

    func testV3BuiltInLightPapersDimMoreThanV2LightAverage() {
        let v2Light = TexturePreset.light.map(TexturePreset.init(v2:))
        let v2Average = v2Light
            .map { dimmingOverWhite(preset: $0, windowAlpha: defaultIntensity).dimming }
            .reduce(0, +) / Double(v2Light.count)

        var weak: [String] = []
        for id in ["gesso-ground", "linen-veil", "parchment-grain"] {
            let dimming = dimmingOverWhite(preset: TexturePreset.preset(id: id), windowAlpha: defaultIntensity).dimming
            if dimming < v2Average {
                weak.append(String(format: "%@ %.2f%% < v2 avg %.2f%%", id, dimming * 100, v2Average * 100))
            }
        }
        XCTAssertTrue(
            weak.isEmpty,
            "v3 glare-reducing built-ins should dim more than the v2 light-paper average: \(weak.joined(separator: "; "))"
        )
    }

    func testV3BuiltInDarkPaperDimSubstantially() {
        let dimming = dimmingOverWhite(preset: TexturePreset.preset(id: "slate-veil"), windowAlpha: defaultIntensity).dimming
        XCTAssertGreaterThan(
            dimming, 0.10,
            "slate-veil at default intensity should dim white ≥ 10%"
        )
    }

    // MARK: - Measurement helpers

    private struct Stats {
        var meanAlpha: Double
        var meanTileAlpha: Double
        var dimming: Double
        var blueReduction: Double
    }

    /// Composites the overlay tile over sRGB white through the same
    /// source-over × window-alpha model OverlayController uses.
    private func dimmingOverWhite(preset: TexturePreset, windowAlpha: Double) -> Stats {
        let tile = TextureRenderer.compositeTile(for: preset, backingScale: 1)
        guard
            let cgImage = tile.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let provider = cgImage.dataProvider,
            let cfData = provider.data
        else {
            XCTFail("\(preset.name): expected composite tile pixels")
            return Stats(meanAlpha: 0, meanTileAlpha: 0, dimming: 0, blueReduction: 0)
        }

        let bytes = [UInt8](cfData as Data)
        let width = cgImage.width
        let height = cgImage.height
        let rowBytes = cgImage.bytesPerRow
        let window = windowAlpha

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumA = 0.0, sumTileA = 0.0
        let count = Double(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                let pr = Double(bytes[offset]) / 255.0
                let pg = Double(bytes[offset + 1]) / 255.0
                let pb = Double(bytes[offset + 2]) / 255.0
                let pa = Double(bytes[offset + 3]) / 255.0
                let srcA = pa * window
                // Premultiplied source-over white:
                // out = src_pre * window + dst * (1 - srcA)
                sumR += pr * window + (1.0 - srcA)
                sumG += pg * window + (1.0 - srcA)
                sumB += pb * window + (1.0 - srcA)
                sumA += srcA
                sumTileA += pa
            }
        }

        let meanR = sumR / count
        let meanG = sumG / count
        let meanB = sumB / count
        let lWhite = luminance(r: 1, g: 1, b: 1)
        let lOut = luminance(r: meanR, g: meanG, b: meanB)
        let linearBlueWhite = linearise(1)
        let linearBlueOut = linearise(meanB)

        return Stats(
            meanAlpha: sumA / count,
            meanTileAlpha: sumTileA / count,
            dimming: max(0, 1 - lOut / lWhite),
            blueReduction: max(0, 1 - linearBlueOut / linearBlueWhite)
        )
    }

    private func washModelDimming(preset: TexturePreset, intensity: Double) -> Double {
        guard let tint = preset.tint.usingColorSpace(.sRGB) else { return 0 }
        let veil = intensity * Double(preset.tintAlpha)
        let r = (1 - veil) + Double(tint.redComponent) * veil
        let g = (1 - veil) + Double(tint.greenComponent) * veil
        let b = (1 - veil) + Double(tint.blueComponent) * veil
        return max(0, 1 - luminance(r: r, g: g, b: b))
    }

    private func linearise(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(r: Double, g: Double, b: Double) -> Double {
        0.2126 * linearise(r) + 0.7152 * linearise(g) + 0.0722 * linearise(b)
    }
}
