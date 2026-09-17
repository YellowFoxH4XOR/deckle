import XCTest
@testable import Deckle

final class PaperFilesTests: XCTestCase {
    private func samplePaper() -> CustomPaper {
        var paper = CustomPaper()
        paper.id = "custom-original"
        paper.name = "Round Trip"
        paper.tintRed = 0.5
        paper.tintGreen = 0.6
        paper.tintBlue = 0.7
        paper.wash = 0.25
        paper.seed = 0xDEAD_BEEF
        return paper
    }

    func testRoundTripPreservesEverythingExceptID() throws {
        let original = samplePaper()
        let decoded = try PaperFiles.decode(try PaperFiles.encode(original))

        XCTAssertNotEqual(decoded.id, original.id)
        XCTAssertTrue(decoded.id.hasPrefix("custom-"))
        var normalized = decoded
        normalized.id = original.id
        XCTAssertEqual(normalized, original)
    }

    func testDecodeAssignsFreshIDEveryTime() throws {
        let data = try PaperFiles.encode(samplePaper())
        let first = try PaperFiles.decode(data)
        let second = try PaperFiles.decode(data)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testDecodeRejectsMalformedJSON() {
        XCTAssertThrowsError(try PaperFiles.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try PaperFiles.decode(Data("{\"name\": 42}".utf8)))
    }

    func testImportAppendsGoodFilesAndReportsBadOnes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperFilesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let good = directory.appendingPathComponent("good.decklepaper.json")
        try PaperFiles.encode(samplePaper()).write(to: good)
        let malformed = directory.appendingPathComponent("bad.decklepaper.json")
        try Data("{".utf8).write(to: malformed)
        let missing = directory.appendingPathComponent("missing.decklepaper.json")

        var papers = [CustomPaper]()
        let failures = PaperFiles.importPapers(urls: [good, malformed, missing], into: &papers)

        XCTAssertEqual(papers.count, 1)
        XCTAssertEqual(papers.first?.name, "Round Trip")
        XCTAssertNotEqual(papers.first?.id, "custom-original")
        XCTAssertEqual(failures.map(\.url), [malformed, missing])
        XCTAssertTrue(failures.allSatisfy { !$0.message.isEmpty })
    }
}
