import XCTest
@testable import Deckle

final class PaperComfortTests: XCTestCase {
    func testVeilComputationAndNearZeroVeilBaseline() {
        let paper = CustomPaper(wash: 0.10)
        let comfort = PaperComfort.evaluate(paper: paper, intensity: 0.05)
        XCTAssertEqual(comfort.veil, 0.005, accuracy: 1e-9)
        XCTAssertEqual(comfort.contrastRatio, 20.8349, accuracy: 1e-3)
        XCTAssertLessThan(comfort.contrastRatio, 21.0)
    }

    func testContrastMonotonicallyDecreasesWithIncreasingWash() {
        let paper1 = CustomPaper(tintRed: 0.95, tintGreen: 0.92, tintBlue: 0.86, wash: 0.10)
        let paper2 = CustomPaper(tintRed: 0.95, tintGreen: 0.92, tintBlue: 0.86, wash: 0.35)
        let paper3 = CustomPaper(tintRed: 0.95, tintGreen: 0.92, tintBlue: 0.86, wash: 0.60)

        let intensity = 0.30
        let c1 = PaperComfort.evaluate(paper: paper1, intensity: intensity)
        let c2 = PaperComfort.evaluate(paper: paper2, intensity: intensity)
        let c3 = PaperComfort.evaluate(paper: paper3, intensity: intensity)

        XCTAssertGreaterThan(c1.contrastRatio, c2.contrastRatio)
        XCTAssertGreaterThan(c2.contrastRatio, c3.contrastRatio)
    }

    func testBlueReductionUsesLinearLightAndClampedIntensity() {
        // tintBlue = 0.5, wash = 0.4, intensity = 0.5 (clamped to 0.45)
        // veil = 0.45 * 0.4 = 0.18; the composited blue channel is 0.91.
        let paper = CustomPaper(tintBlue: 0.5, wash: 0.4)
        let comfort = PaperComfort.evaluate(paper: paper, intensity: 0.5)

        XCTAssertEqual(comfort.veil, 0.18, accuracy: 1e-9)
        XCTAssertEqual(comfort.blueReduction, 0.1926540911, accuracy: 1e-9)
    }

    func testPureWhiteTintHasZeroBlueReductionAndD65Temperature() {
        let paper = CustomPaper(tintRed: 1.0, tintGreen: 1.0, tintBlue: 1.0, wash: 0.40)
        let comfort = PaperComfort.evaluate(paper: paper, intensity: 0.25)

        XCTAssertEqual(comfort.blueReduction, 0.0, accuracy: 1e-9)
        XCTAssertEqual(comfort.temperature, 6504.0, accuracy: 100.0)
    }

    func testWhiteTintMaxVeilHasWorstReachableContrastGrade() {
        let paper = CustomPaper(tintRed: 1.0, tintGreen: 1.0, tintBlue: 1.0, wash: 0.60)
        let comfort = PaperComfort.evaluate(paper: paper, intensity: 0.45)

        XCTAssertEqual(comfort.veil, 0.27, accuracy: 1e-9)
        XCTAssertEqual(comfort.contrastRatio, 9.61, accuracy: 0.10)
        XCTAssertEqual(comfort.grade, .poor)
        XCTAssertTrue(comfort.needsContrastWarning)
    }

    func testEveryComfortGradeIsReachable() {
        func whitePaper(wash: Double) -> CustomPaper {
            CustomPaper(tintRed: 1, tintGreen: 1, tintBlue: 1, wash: wash)
        }

        let excellent = PaperComfort.evaluate(paper: whitePaper(wash: 0.10), intensity: 0.05)
        let good = PaperComfort.evaluate(paper: whitePaper(wash: 0.40), intensity: 0.25)
        let reduced = PaperComfort.evaluate(paper: whitePaper(wash: 0.50), intensity: 0.40)
        let poor = PaperComfort.evaluate(paper: whitePaper(wash: 0.60), intensity: 0.45)

        XCTAssertEqual(excellent.grade, .excellent)
        XCTAssertEqual(good.grade, .good)
        XCTAssertEqual(reduced.grade, .reduced)
        XCTAssertEqual(poor.grade, .poor)
        XCTAssertFalse(excellent.needsContrastWarning)
        XCTAssertFalse(good.needsContrastWarning)
        XCTAssertTrue(reduced.needsContrastWarning)
        XCTAssertTrue(poor.needsContrastWarning)
    }

    func testDimmingAndPatternLoadValues() {
        let dark = CustomPaper(
            tintRed: 0,
            tintGreen: 0,
            tintBlue: 0,
            wash: 0.60,
            weave: 0.35,
            blotch: 0
        )
        let comfort = PaperComfort.evaluate(paper: dark, intensity: 0.45)
        XCTAssertEqual(comfort.dimming, 0.508095, accuracy: 1e-4)
        XCTAssertEqual(comfort.patternLoad, 0.7, accuracy: 1e-9)

        let white = CustomPaper(
            tintRed: 1,
            tintGreen: 1,
            tintBlue: 1,
            wash: 0.60,
            weave: 0,
            blotch: 0.40
        )
        let bright = PaperComfort.evaluate(paper: white, intensity: 0.45)
        XCTAssertEqual(bright.dimming, 0, accuracy: 1e-9)
        XCTAssertEqual(bright.patternLoad, 0.3, accuracy: 1e-9)
    }

    func testInputClampingProducesIdenticalEvaluation() {
        let unclamped = CustomPaper(
            tintRed: -1.0,
            tintGreen: 2.0,
            tintBlue: 1.5,
            wash: 5.0,
            weave: 9.0,
            blotch: -3.0
        )
        let clampedExpected = CustomPaper(
            tintRed: 0.0,
            tintGreen: 1.0,
            tintBlue: 1.0,
            wash: 0.60,
            weave: 0.35,
            blotch: 0.0
        )

        let eval1 = PaperComfort.evaluate(paper: unclamped, intensity: 0.30)
        let eval2 = PaperComfort.evaluate(paper: clampedExpected, intensity: 0.30)

        XCTAssertEqual(eval1.veil, eval2.veil, accuracy: 1e-9)
        XCTAssertEqual(eval1.dimming, eval2.dimming, accuracy: 1e-9)
        XCTAssertEqual(eval1.contrastRatio, eval2.contrastRatio, accuracy: 1e-9)
        XCTAssertEqual(eval1.blueReduction, eval2.blueReduction, accuracy: 1e-9)
        XCTAssertEqual(eval1.temperature, eval2.temperature, accuracy: 1e-9)
        XCTAssertEqual(eval1.patternLoad, eval2.patternLoad, accuracy: 1e-9)
        XCTAssertEqual(eval1.grade, eval2.grade)
    }

    func testComfortRecipePreservesIdentityAndAppliesVisuals() {
        var paper = CustomPaper(
            id: "custom-special-id-123",
            name: "My Unsaved Custom Paper",
            tintRed: 0.1,
            tintGreen: 0.2,
            tintBlue: 0.3,
            wash: 0.15,
            weave: 0.05,
            blotch: 0.05,
            engineVersion: .spectral,
            seed: 987654321
        )

        let recipe = PaperComfort.recipes.first { $0.id == "night" }!
        recipe.apply(to: &paper)

        // Identity must be preserved
        XCTAssertEqual(paper.id, "custom-special-id-123")
        XCTAssertEqual(paper.name, "My Unsaved Custom Paper")
        XCTAssertEqual(paper.seed, 987654321)
        XCTAssertEqual(paper.engineVersion, .spectral)

        // Visuals must match recipe
        XCTAssertEqual(paper.tintRed, recipe.tint.r, accuracy: 1e-9)
        XCTAssertEqual(paper.tintGreen, recipe.tint.g, accuracy: 1e-9)
        XCTAssertEqual(paper.tintBlue, recipe.tint.b, accuracy: 1e-9)
        XCTAssertEqual(paper.wash, recipe.wash, accuracy: 1e-9)
        XCTAssertEqual(paper.weave, recipe.weave, accuracy: 1e-9)
        XCTAssertEqual(paper.blotch, recipe.blotch, accuracy: 1e-9)
    }
}
