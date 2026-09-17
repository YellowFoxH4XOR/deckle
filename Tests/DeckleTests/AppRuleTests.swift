import XCTest
@testable import Deckle

final class AppRuleTests: XCTestCase {
    private let editor = "test.editor"
    private let browser = "test.browser"

    private func withState(_ body: (AppState) throws -> Void) throws {
        let suite = "DeckleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.ruleApps = [.init(bundleID: editor, name: "Editor")]
        try body(state)
    }

    // MARK: appRuleAllows

    func testEverywhereAllowsListedUnlistedAndUnknownApps() throws {
        try withState { state in
            state.appRuleMode = .everywhere
            XCTAssertTrue(state.appRuleAllows(frontmost: editor))
            XCTAssertTrue(state.appRuleAllows(frontmost: browser))
            XCTAssertTrue(state.appRuleAllows(frontmost: nil))
        }
    }

    func testExceptBlocksOnlyListedApps() throws {
        try withState { state in
            state.appRuleMode = .except
            XCTAssertFalse(state.appRuleAllows(frontmost: editor))
            XCTAssertTrue(state.appRuleAllows(frontmost: browser))
        }
    }

    func testOnlyAllowsOnlyListedApps() throws {
        try withState { state in
            state.appRuleMode = .only
            XCTAssertTrue(state.appRuleAllows(frontmost: editor))
            XCTAssertFalse(state.appRuleAllows(frontmost: browser))
        }
    }

    func testUnknownFrontmostIsAllowedInEveryMode() throws {
        try withState { state in
            for mode in AppState.AppRuleMode.allCases {
                state.appRuleMode = mode
                XCTAssertTrue(state.appRuleAllows(frontmost: nil), "\(mode)")
            }
        }
    }

    func testOwnBundleIsAlwaysAllowedEvenWhenListed() throws {
        guard let own = Bundle.main.bundleIdentifier else {
            throw XCTSkip("Test host has no bundle identifier")
        }
        try withState { state in
            state.ruleApps = [.init(bundleID: own, name: "Deckle")]
            for mode in AppState.AppRuleMode.allCases {
                state.appRuleMode = mode
                XCTAssertTrue(state.appRuleAllows(frontmost: own), "\(mode)")
            }
            state.appRuleMode = .only
            state.ruleApps = []
            XCTAssertTrue(state.appRuleAllows(frontmost: own))
        }
    }

    func testEmptyRuleListMakesExceptShowAndOnlyHide() throws {
        try withState { state in
            state.ruleApps = []
            state.appRuleMode = .except
            XCTAssertTrue(state.appRuleAllows(frontmost: browser))
            state.appRuleMode = .only
            XCTAssertFalse(state.appRuleAllows(frontmost: browser))
        }
    }

    // MARK: overlayIsVisible

    func testVisibleByDefaultAndFollowsAppRules() throws {
        try withState { state in
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: browser))
            state.appRuleMode = .except
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: editor))
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: browser))
            state.appRuleMode = .only
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: editor))
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: browser))
        }
    }

    func testExcludedDisplayHidesRegardlessOfRulesAndPreview() throws {
        try withState { state in
            state.excludedDisplays = ["2"]
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: browser))
            XCTAssertFalse(state.overlayIsVisible(on: "2", frontmost: browser))
            state.previewPaper = CustomPaper(seed: 7)
            XCTAssertFalse(state.overlayIsVisible(on: "2", frontmost: browser))
        }
    }

    func testDisabledOrSnoozedHidesUnlessPreviewing() throws {
        try withState { state in
            state.isEnabled = false
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: browser))
            state.isEnabled = true
            state.snooze(minutes: 30)
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: browser))
            state.previewPaper = CustomPaper(seed: 7)
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: browser))
            state.cancelSnooze()
            state.previewPaper = nil
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: browser))
        }
    }

    func testComparingOriginalHidesEvenWhilePreviewing() throws {
        try withState { state in
            state.previewPaper = CustomPaper(seed: 7)
            state.isComparingOriginal = true
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: browser))
            state.isComparingOriginal = false
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: browser))
        }
    }

    func testPreviewPaperOverridesAppRules() throws {
        try withState { state in
            state.appRuleMode = .only
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: browser))
            state.previewPaper = CustomPaper(seed: 7)
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: browser))
            state.appRuleMode = .except
            XCTAssertTrue(state.overlayIsVisible(on: "1", frontmost: editor))
            state.previewPaper = nil
            XCTAssertFalse(state.overlayIsVisible(on: "1", frontmost: editor))
        }
    }
}
