import XCTest
@testable import Deckle

final class InputValidationTests: XCTestCase {
    @MainActor
    func testAutomationRejectsNonFiniteNumbers() throws {
        let suite = "DeckleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        for value in ["nan", "inf", "-inf"] {
            URLCommands.handle(try XCTUnwrap(URL(string: "deckle://intensity?percent=\(value)")), state: state)
            XCTAssertEqual(state.intensity, 0.22)
            URLCommands.handle(try XCTUnwrap(URL(string: "deckle://grain?size=\(value)&strength=\(value)")), state: state)
            XCTAssertEqual(state.grainScale, 1)
            XCTAssertEqual(state.grainStrength, 1)
        }
    }

    func testImportedPaperClassificationUsesClampedTint() throws {
        var paper = CustomPaper(tintRed: -10, tintGreen: 1, tintBlue: 1, seed: 123)
        let imported = try JSONDecoder().decode(CustomPaper.self, from: JSONEncoder().encode(paper))
        paper.tintRed = 0
        let normalized = TexturePreset(custom: paper)
        let actual = TexturePreset(custom: imported)
        XCTAssertEqual(actual.isDark, normalized.isDark)
        XCTAssertEqual(actual.darkStrength, normalized.darkStrength)
        XCTAssertEqual(actual.lightStrength, normalized.lightStrength)
    }
}
