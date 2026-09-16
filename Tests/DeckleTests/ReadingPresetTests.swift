import XCTest
import AppKit
@testable import Deckle

/// Engineering checks on rendered sRGB samples, not clinical comfort scores.
final class ReadingPresetTests: XCTestCase {
    struct Measurement {
        let dimming: Double
        let variation: Double
        let lightTextContrast: Double
        let darkTextContrast: Double
    }

    func testQuietCollectionHasMuchLessPatternVariationThanSoftWove() throws {
        let baseline = try measure(TexturePreset.preset(id: "classic-matte"), intensity: 0.22)
        for preset in TexturePreset.readingCollection {
            let result = try measure(preset, intensity: 0.22)
            XCTAssertLessThan(result.variation, baseline.variation * 0.20, preset.name)
            XCTAssertGreaterThan(result.dimming, 0.02, preset.name)
            XCTAssertLessThan(result.dimming, 0.22, preset.name)
            print(String(format: "READING %@: white dim %.2f%%; texture SD %.4f%%; gray/white %.2f:1; light/dark %.2f:1",
                         preset.name, result.dimming * 100, result.variation * 100,
                         result.lightTextContrast, result.darkTextContrast))
        }
        print(String(format: "READING Soft Wove baseline: texture SD %.4f%%", baseline.variation * 100))
    }

    func testReadableSamplePairsAtRecommendedIntensityAcrossBackingScales() throws {
        for scale: CGFloat in [1, 2] {
            for preset in TexturePreset.readingCollection {
                let result = try measure(preset, intensity: 0.22, backingScale: scale)
                // Conservative: foreground and background may fall on different
                // extrema of the tile. This tests these pairs, not every app.
                XCTAssertGreaterThanOrEqual(result.lightTextContrast, 4.5, preset.name)
                XCTAssertGreaterThanOrEqual(result.darkTextContrast, 7, preset.name)
            }
        }
    }

    func testClearVeilIsUniformAndQuietRecipesAreDeterministic() throws {
        for preset in TexturePreset.readingCollection {
            TextureRenderer.resetCaches()
            let first = try pixels(preset, backingScale: 1)
            TextureRenderer.resetCaches()
            XCTAssertEqual(first, try pixels(preset, backingScale: 1), preset.name)
        }
        let clear = try measure(TexturePreset.preset(id: "clear-veil"), intensity: 0.45)
        XCTAssertLessThan(clear.variation, 0.000001)
    }

    func testReadingPresetsKeepOriginalLibraryAndUniqueStableIDs() {
        XCTAssertEqual(TexturePreset.readingCollection.count, 4)
        XCTAssertEqual(TexturePreset.all.count, 26)
        XCTAssertEqual(Set(TexturePreset.all.map(\.id)).count, TexturePreset.all.count)
        XCTAssertEqual(TexturePreset.preset(id: "classic-matte").name, "Soft Wove")
        for setup in DeskSetup.starters {
            XCTAssertTrue(TexturePreset.readingCollection.contains { $0.id == setup.textureID })
        }
    }

    func testQuietGrainStrengthsRoundTripInCustomPapersAndClampImports() throws {
        let paper = CustomPaper(seed: 17, darkGrainStrength: 0, lightGrainStrength: 0)
        let decoded = try JSONDecoder().decode(CustomPaper.self, from: JSONEncoder().encode(paper))
        let preset = TexturePreset(custom: decoded)
        XCTAssertEqual(preset.darkStrength, 0)
        XCTAssertEqual(preset.lightStrength, 0)
        XCTAssertLessThan(try measure(preset, intensity: 0.22).variation, 0.000001)
        let imported = TexturePreset(custom: CustomPaper(seed: 17, darkGrainStrength: -10, lightGrainStrength: 20))
        XCTAssertEqual(imported.darkStrength, 0)
        XCTAssertEqual(imported.lightStrength, 1)
    }

    private func pixels(_ preset: TexturePreset, backingScale: CGFloat) throws -> [UInt8] {
        let image = TextureRenderer.compositeTile(for: preset, backingScale: backingScale)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: cg.width, height: cg.height,
                                              bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let data = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: cg.width * cg.height * 4))
    }

    private func measure(_ preset: TexturePreset, intensity: Double, backingScale: CGFloat = 1) throws -> Measurement {
        let bytes = try pixels(preset, backingScale: backingScale)
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var whites: [Double] = []
        var minWhite = 1.0, maxGray = 0.0, minLight = 1.0, maxDark = 0.0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let a = Double(bytes[offset + 3]) / 255 * intensity
            func luminance(over background: Double) -> Double {
                let r = Double(bytes[offset]) / 255 * intensity + background * (1 - a)
                let g = Double(bytes[offset + 1]) / 255 * intensity + background * (1 - a)
                let b = Double(bytes[offset + 2]) / 255 * intensity + background * (1 - a)
                return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
            }
            let white = luminance(over: 1)
            whites.append(white)
            minWhite = min(minWhite, white)
            maxGray = max(maxGray, luminance(over: 0.42))
            minLight = min(minLight, luminance(over: 0.8))
            maxDark = max(maxDark, luminance(over: 0.1333))
        }
        let mean = whites.reduce(0, +) / Double(whites.count)
        let variance = whites.reduce(0) { $0 + pow($1 - mean, 2) } / Double(whites.count)
        return Measurement(dimming: 1 - mean, variation: sqrt(variance),
                           lightTextContrast: (minWhite + 0.05) / (maxGray + 0.05),
                           darkTextContrast: (minLight + 0.05) / (maxDark + 0.05))
    }
}
