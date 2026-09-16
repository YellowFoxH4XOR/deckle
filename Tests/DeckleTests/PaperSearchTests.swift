import XCTest
@testable import Deckle

final class PaperSearchTests: XCTestCase {
    func testSearchHandlesRepeatedWhitespaceAndReorderedMaterialTerms() {
        let paper = TexturePreset.preset(id: "classic-matte")
        XCTAssertTrue(PaperSearch.matches(paper, query: "  SOFT  \n WOVE ", isCustom: false))
        XCTAssertTrue(PaperSearch.matches(paper, query: "smooth soft", isCustom: false))
        XCTAssertFalse(PaperSearch.matches(paper, query: "soft dark", isCustom: false))
    }

    func testSearchIncludesCustomMetadataWithoutLosingAccents() {
        let paper = TexturePreset(custom: CustomPaper(name: "Crème", seed: 5))
        XCTAssertTrue(PaperSearch.matches(paper, query: "creme custom", isCustom: true))
        XCTAssertFalse(PaperSearch.matches(paper, query: "built in", isCustom: true))
    }
}
