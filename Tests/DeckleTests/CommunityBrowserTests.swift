import XCTest
@testable import Deckle

final class CommunityBrowserTests: XCTestCase {
    func testSanitizedPathRemovesEveryParentDirectorySequence() {
        XCTAssertEqual(CommunityBrowser.sanitizedPath("linen.json"), "linen.json")
        XCTAssertEqual(CommunityBrowser.sanitizedPath("../secret.json"), "/secret.json")
        XCTAssertEqual(CommunityBrowser.sanitizedPath("../../a/../b.json"), "///a//b.json")
        XCTAssertEqual(CommunityBrowser.sanitizedPath("....//x.json"), "//x.json")
        XCTAssertFalse(CommunityBrowser.sanitizedPath(".../...//...json").contains(".."))
    }

    func testImportedPaperAlwaysGetsFreshCustomID() throws {
        let paper = CustomPaper(id: "builtin-parchment", name: "Shared", seed: 7)
        let data = try JSONEncoder().encode(paper)

        let first = try CommunityBrowser.importedPaper(from: data)
        let second = try CommunityBrowser.importedPaper(from: data)

        XCTAssertTrue(first.id.hasPrefix("custom-"))
        XCTAssertTrue(second.id.hasPrefix("custom-"))
        XCTAssertNotEqual(first.id, "builtin-parchment")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.name, "Shared")
        XCTAssertEqual(first.seed, paper.seed)
    }

    func testImportedPaperRejectsMalformedJSON() {
        XCTAssertThrowsError(try CommunityBrowser.importedPaper(from: Data("not json".utf8)))
    }
}
