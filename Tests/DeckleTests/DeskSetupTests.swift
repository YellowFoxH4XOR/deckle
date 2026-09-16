import XCTest
@testable import Deckle

final class DeskSetupTests: XCTestCase {
    private func withState(_ body: (AppState, UserDefaults) throws -> Void) throws {
        let suite = "DeckleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppState(defaults: defaults), defaults)
    }

    func testSavedSetupSurvivesRelaunchAndRestoresAllControls() throws {
        try withState { state, defaults in
            state.textureID = "rice-paper"
            state.intensity = 0.31
            state.grainScale = 2
            state.grainStrength = 1.25
            state.matteStrength = 0.37
            XCTAssertTrue(state.saveDeskSetup(name: "  Deep reading  "))
            let relaunched = AppState(defaults: defaults)
            let setup = try XCTUnwrap(relaunched.deskSetups.last)
            XCTAssertEqual(setup.name, "Deep reading")
            XCTAssertEqual(setup.matteStrength, 0.37)
            relaunched.textureID = "espresso"
            relaunched.snooze(minutes: 30)
            relaunched.isEnabled = false
            relaunched.isComparingOriginal = true
            XCTAssertTrue(relaunched.apply(setup))
            XCTAssertTrue(relaunched.matches(setup))
            XCTAssertEqual(relaunched.matteStrength, 0.37)
            XCTAssertTrue(relaunched.shouldShowOverlay)
            XCTAssertFalse(relaunched.isComparingOriginal)
        }
    }

    func testOlderSetupWithoutMatteMigratesToZero() throws {
        let json = """
        {
            "name": "Legacy",
            "textureID": "clear-veil",
            "intensity": 0.22,
            "grainScale": 1,
            "grainStrength": 1
        }
        """.data(using: .utf8)!
        let setup = try JSONDecoder().decode(DeskSetup.self, from: json)
        XCTAssertEqual(setup.matteStrength, 0)
        XCTAssertTrue(setup.hasValidSettings)
    }

    func testMissingPaperAndLiveDraftPreventSetupApplication() throws {
        try withState { state, _ in
            let original = state.textureID
            var missing = DeskSetup.starters[0]
            missing.textureID = "custom-deleted"
            XCTAssertFalse(state.apply(missing))
            XCTAssertEqual(state.textureID, original)
            state.previewPaper = CustomPaper(seed: 7)
            XCTAssertFalse(state.apply(DeskSetup.starters[2]))
            XCTAssertFalse(state.saveDeskSetup(name: "Unsaved draft"))
            XCTAssertEqual(state.textureID, original)
            XCTAssertNotNil(state.previewPaper)
        }
    }

    func testComparePreservesSnoozeAndPreviewButNeverOverridesExclusions() throws {
        try withState { state, _ in
            state.snooze(minutes: 30)
            let until = state.snoozeUntil
            state.previewPaper = CustomPaper(seed: 7)
            state.excludedDisplays = ["2"]
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: nil))
            XCTAssertFalse(state.overlayIsVisible(on: "2", frontmost: nil))
            state.isComparingOriginal = true
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: nil))
            state.isComparingOriginal = false
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: nil))
            XCTAssertEqual(state.snoozeUntil, until)
            state.previewPaper = nil
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: nil))
        }
    }

    func testComparisonIsTransientAndRulesRemainAuthoritative() throws {
        try withState { state, defaults in
            state.appRuleMode = .only
            state.ruleApps = [.init(bundleID: "test.editor", name: "Editor")]
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: "test.browser"))
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: "test.editor"))
            state.isComparingOriginal = true
            XCTAssertFalse(AppState(defaults: defaults).isComparingOriginal)
        }
    }

    func testSaveValidationAndRemovingAllSetupsPersistsEmptyLibrary() throws {
        try withState { state, defaults in
            XCTAssertFalse(state.saveDeskSetup(name: " \n "))
            for index in 0..<5 { XCTAssertTrue(state.saveDeskSetup(name: "Setup \(index)")) }
            XCTAssertFalse(state.saveDeskSetup(name: "Overflow"))
            state.deskSetups = []
            XCTAssertTrue(AppState(defaults: defaults).deskSetups.isEmpty)
        }
    }

    func testInvalidStoredNumbersRecoverToUsableDefaults() throws {
        try withState { _, defaults in
            defaults.set(Double.nan, forKey: "intensity")
            defaults.set(Double.infinity, forKey: "grainScale")
            defaults.set(-100.0, forKey: "grainStrength")
            defaults.set(Double.infinity, forKey: "matteStrength")
            let recovered = AppState(defaults: defaults)
            XCTAssertEqual(recovered.intensity, 0.22)
            XCTAssertEqual(recovered.grainScale, 1)
            XCTAssertEqual(recovered.grainStrength, 0.25)
            XCTAssertEqual(recovered.matteStrength, 0)
        }
    }
}
