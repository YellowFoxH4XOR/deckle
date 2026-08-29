import Foundation

/// Evaluates eye-comfort metrics for a custom paper texture composited
/// over screen content at a given overlay intensity.
///
/// Models the overlay compositing pipeline: `veil = intensity × wash`, with screen
/// colour `c` transformed to `c' = c·(1 − veil) + tint·veil`.
struct PaperComfort: Equatable {
    /// Net veil opacity reaching the screen (intensity × wash), 0…1.
    let veil: Double
    /// Fraction of a pure-white screen's relative luminance removed by the veil.
    let dimming: Double
    /// WCAG 2.1 contrast ratio between white and black content seen through the paper.
    let contrastRatio: Double
    /// Fraction of a white screen's blue-channel light removed by the tint wash.
    let blueReduction: Double
    /// Correlated Colour Temperature of the tint wash in Kelvin (McCamy approximation).
    let temperature: Double
    /// Combined structural prominence of weave and blotch patterns, 0…1.
    let patternLoad: Double

    enum Grade: String, Equatable {
        case excellent = "Excellent retention"
        case good = "Good retention"
        case reduced = "Reduced contrast"
        case poor = "Heavy contrast loss"
    }

    var grade: Grade

    var needsContrastWarning: Bool {
        grade == .reduced || grade == .poor
    }

    static func evaluate(paper: CustomPaper, intensity: Double) -> PaperComfort {
        func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
            min(max(v, range.lowerBound), range.upperBound)
        }

        let r = clamp(paper.tintRed, 0...1)
        let g = clamp(paper.tintGreen, 0...1)
        let b = clamp(paper.tintBlue, 0...1)
        let wash = clamp(paper.wash, 0.10...0.60)
        let weave = clamp(paper.weave, 0...0.35)
        let blotch = clamp(paper.blotch, 0...0.40)
        let clampedIntensity = clamp(intensity, 0.05...0.45)

        let veil = clampedIntensity * wash

        // Composite white (1, 1, 1) and black (0, 0, 0) through the tint wash
        let whiteCompR = (1.0 - veil) + r * veil
        let whiteCompG = (1.0 - veil) + g * veil
        let whiteCompB = (1.0 - veil) + b * veil

        let blackCompR = r * veil
        let blackCompG = g * veil
        let blackCompB = b * veil

        // WCAG 2.1 sRGB linearisation and relative luminance: L = 0.2126·R + 0.7152·G + 0.0722·B
        func linearise(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        func luminance(r: Double, g: Double, b: Double) -> Double {
            0.2126 * linearise(r) + 0.7152 * linearise(g) + 0.0722 * linearise(b)
        }

        let lWhite = luminance(r: whiteCompR, g: whiteCompG, b: whiteCompB)
        let lBlack = luminance(r: blackCompR, g: blackCompG, b: blackCompB)

        let dimming = max(0, min(1, 1.0 - lWhite))
        let contrastRatio = (lWhite + 0.05) / (lBlack + 0.05)
        let blueReduction = max(0, min(1, 1.0 - linearise((1.0 - veil) + b * veil)))

        // Correlated Colour Temperature (CCT) via McCamy's formula
        let linR = linearise(r)
        let linG = linearise(g)
        let linB = linearise(b)

        let xVal = 0.4124564 * linR + 0.3575761 * linG + 0.1804375 * linB
        let yVal = 0.2126729 * linR + 0.7151522 * linG + 0.0721750 * linB
        let zVal = 0.0193339 * linR + 0.1191920 * linG + 0.9503041 * linB

        let sumXYZ = xVal + yVal + zVal
        let temperature: Double
        if sumXYZ <= 1e-6 {
            temperature = 6504.0
        } else {
            let chrX = xVal / sumXYZ
            let chrY = yVal / sumXYZ
            let denom = 0.1858 - chrY
            if abs(denom) < 1e-6 {
                temperature = 6504.0
            } else {
                let n = (chrX - 0.3320) / denom
                let cct = 437.0 * pow(n, 3) + 3601.0 * pow(n, 2) + 6861.0 * n + 5517.0
                temperature = max(1000, min(25000, cct))
            }
        }

        let patternLoad = min(1.0, 0.7 * (weave / 0.35) + 0.3 * (blotch / 0.40))

        // Grade the contrast retained relative to a bare screen's 21:1
        // white-on-black baseline. Absolute WCAG thresholds are not useful
        // here: the clamped veil can never push contrast below about 9.6:1.
        let contrastRetention = contrastRatio / 21.0
        let grade: Grade
        if contrastRetention >= 0.85 {
            grade = .excellent
        } else if contrastRetention >= 0.70 {
            grade = .good
        } else if contrastRetention >= 0.55 {
            grade = .reduced
        } else {
            grade = .poor
        }

        return PaperComfort(
            veil: veil,
            dimming: dimming,
            contrastRatio: contrastRatio,
            blueReduction: blueReduction,
            temperature: temperature,
            patternLoad: patternLoad,
            grade: grade
        )
    }

    /// Curated starting points designed for specific viewing scenarios.
    static let recipes: [ComfortRecipe] = [
        ComfortRecipe(
            id: "focus",
            name: "Focus",
            detail: "Near-neutral, keeps text crispest",
            tint: (r: 0.98, g: 0.97, b: 0.96),
            wash: 0.18,
            weave: 0.00,
            blotch: 0.00
        ),
        ComfortRecipe(
            id: "reading",
            name: "Reading",
            detail: "Warm off-white for long sessions",
            tint: (r: 0.97, g: 0.94, b: 0.88),
            wash: 0.32,
            weave: 0.06,
            blotch: 0.05
        ),
        ComfortRecipe(
            id: "paper",
            name: "Paper",
            detail: "Classic warm laid stock",
            tint: (r: 0.95, g: 0.92, b: 0.86),
            wash: 0.40,
            weave: 0.18,
            blotch: 0.12
        ),
        ComfortRecipe(
            id: "night",
            name: "Night",
            detail: "Deep amber, strongest blue cut",
            tint: (r: 0.96, g: 0.82, b: 0.60),
            wash: 0.50,
            weave: 0.00,
            blotch: 0.10
        )
    ]
}

/// A curated starting configuration for custom papers.
struct ComfortRecipe: Identifiable {
    let id: String
    let name: String
    let detail: String
    let tint: (r: Double, g: Double, b: Double)
    let wash: Double
    let weave: Double
    let blotch: Double

    /// Overwrites only the six visual fields — `id`, `name`, `seed` and
    /// `engineVersion` are the paper's identity and survive.
    func apply(to paper: inout CustomPaper) {
        paper.tintRed = tint.r
        paper.tintGreen = tint.g
        paper.tintBlue = tint.b
        paper.wash = wash
        paper.weave = weave
        paper.blotch = blotch
    }
}
