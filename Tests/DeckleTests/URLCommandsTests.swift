import XCTest
@testable import Deckle

@MainActor
final class URLCommandsTests: XCTestCase {
    private func withState(_ body: (AppState) throws -> Void) throws {
        let suite = "DeckleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppState(defaults: defaults))
    }

    private func handle(_ string: String, state: AppState) throws {
        URLCommands.handle(try XCTUnwrap(URL(string: string)), state: state)
    }

    func testOnEnablesAndCancelsSnooze() throws {
        try withState { state in
            state.isEnabled = false
            state.snooze(minutes: 30)
            try handle("deckle://on", state: state)
            XCTAssertTrue(state.isEnabled)
            XCTAssertNil(state.snoozeUntil)
            XCTAssertTrue(state.shouldShowOverlay)
        }
    }

    func testOffDisables() throws {
        try withState { state in
            state.isEnabled = true
            try handle("deckle://off", state: state)
            XCTAssertFalse(state.isEnabled)
            XCTAssertFalse(state.shouldShowOverlay)
        }
    }

    func testToggleDisablesWhenOverlayShowing() throws {
        try withState { state in
            state.isEnabled = true
            XCTAssertTrue(state.shouldShowOverlay)
            try handle("deckle://toggle", state: state)
            XCTAssertFalse(state.isEnabled)
        }
    }

    func testToggleEnablesWhenDisabled() throws {
        try withState { state in
            state.isEnabled = false
            try handle("deckle://toggle", state: state)
            XCTAssertTrue(state.isEnabled)
            XCTAssertTrue(state.shouldShowOverlay)
        }
    }

    func testToggleWhileSnoozedResumesInsteadOfDisabling() throws {
        try withState { state in
            state.isEnabled = true
            state.snooze(minutes: 30)
            XCTAssertFalse(state.shouldShowOverlay)
            try handle("deckle://toggle", state: state)
            XCTAssertTrue(state.isEnabled)
            XCTAssertNil(state.snoozeUntil)
            XCTAssertTrue(state.shouldShowOverlay)
        }
    }

    func testSnoozeDefaultsToThirtyMinutes() throws {
        try withState { state in
            let before = Date()
            try handle("deckle://snooze", state: state)
            let until = try XCTUnwrap(state.snoozeUntil)
            XCTAssertEqual(until.timeIntervalSince(before), 30 * 60, accuracy: 5)
            XCTAssertTrue(state.isSnoozed)
            XCTAssertFalse(state.shouldShowOverlay)
        }
    }

    func testSnoozeHonorsInRangeMinutes() throws {
        try withState { state in
            let before = Date()
            try handle("deckle://snooze?minutes=45", state: state)
            let until = try XCTUnwrap(state.snoozeUntil)
            XCTAssertEqual(until.timeIntervalSince(before), 45 * 60, accuracy: 5)
        }
    }

    func testSnoozeClampsOutOfRangeMinutes() throws {
        try withState { state in
            var before = Date()
            try handle("deckle://snooze?minutes=0", state: state)
            var until = try XCTUnwrap(state.snoozeUntil)
            XCTAssertEqual(until.timeIntervalSince(before), 60, accuracy: 5)

            before = Date()
            try handle("deckle://snooze?minutes=-15", state: state)
            until = try XCTUnwrap(state.snoozeUntil)
            XCTAssertEqual(until.timeIntervalSince(before), 60, accuracy: 5)

            before = Date()
            try handle("deckle://snooze?minutes=99999", state: state)
            until = try XCTUnwrap(state.snoozeUntil)
            XCTAssertEqual(until.timeIntervalSince(before), 24 * 60 * 60, accuracy: 5)
        }
    }

    func testSnoozeFallsBackToDefaultForMalformedMinutes() throws {
        try withState { state in
            for value in ["abc", "1.5", "", "nan"] {
                let before = Date()
                try handle("deckle://snooze?minutes=\(value)", state: state)
                let until = try XCTUnwrap(state.snoozeUntil)
                XCTAssertEqual(until.timeIntervalSince(before), 30 * 60, accuracy: 5, "minutes=\(value)")
            }
        }
    }

    func testResumeCancelsSnooze() throws {
        try withState { state in
            state.snooze(minutes: 30)
            XCTAssertTrue(state.isSnoozed)
            try handle("deckle://resume", state: state)
            XCTAssertNil(state.snoozeUntil)
            XCTAssertTrue(state.shouldShowOverlay)
        }
    }

    func testTextureMatchesPresetById() throws {
        try withState { state in
            try handle("deckle://texture?id=rice-paper", state: state)
            XCTAssertEqual(state.textureID, "rice-paper")
        }
    }

    func testTextureMatchesPresetByDisplayName() throws {
        try withState { state in
            try handle("deckle://texture?id=Soft%20Wove", state: state)
            XCTAssertEqual(state.textureID, "classic-matte")

            try handle("deckle://texture?name=Ink%20Stone", state: state)
            XCTAssertEqual(state.textureID, "carbon-ledger")
        }
    }

    func testTextureMatchesNormalizedForms() throws {
        try withState { state in
            for query in ["inkstone", "INK-STONE", "ink_stone", "Ink%20Stone", "carbonledger", "Carbon%20Ledger"] {
                state.textureID = "rice-paper"
                try handle("deckle://texture?id=\(query)", state: state)
                XCTAssertEqual(state.textureID, "carbon-ledger", "query=\(query)")
            }
        }
    }

    func testTextureMatchesCustomPaperByIdAndName() throws {
        try withState { state in
            let paper = CustomPaper(id: "custom-abc123", name: "Grandma's Ledger", seed: 7)
            state.customPapers = [paper]

            state.textureID = "rice-paper"
            try handle("deckle://texture?id=custom-abc123", state: state)
            XCTAssertEqual(state.textureID, paper.id)

            state.textureID = "rice-paper"
            try handle("deckle://texture?name=grandmas%20ledger", state: state)
            XCTAssertEqual(state.textureID, paper.id)
        }
    }

    func testTextureIgnoresUnknownOrEmptyId() throws {
        try withState { state in
            state.textureID = "rice-paper"
            for url in [
                "deckle://texture?id=no-such-paper",
                "deckle://texture?id=",
                "deckle://texture?id=123",
                "deckle://texture",
            ] {
                try handle(url, state: state)
                XCTAssertEqual(state.textureID, "rice-paper", url)
            }
        }
    }

    func testUnknownCommandAndForeignSchemeLeaveStateUntouched() throws {
        try withState { state in
            state.isEnabled = true
            state.textureID = "rice-paper"
            try handle("deckle://bogus?minutes=5", state: state)
            try handle("https://toggle", state: state)
            XCTAssertTrue(state.isEnabled)
            XCTAssertNil(state.snoozeUntil)
            XCTAssertEqual(state.textureID, "rice-paper")
        }
    }
}
