import XCTest
import SwiftUI
@testable import Deckle

final class MenuPopoverTests: XCTestCase {
    func testShrinkingContentPreservesTopEdgeOnNegativeCoordinateDisplay() {
        let current = CGRect(x: -1800, y: -700, width: 370, height: 540)
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let resized = MenuPopoverGeometry.frame(
            size: CGSize(width: 370, height: 210), anchoredTo: current, visibleFrame: visible
        )

        XCTAssertEqual(resized.size, CGSize(width: 370, height: 210))
        XCTAssertEqual(resized.maxY, current.maxY)
        XCTAssertEqual(resized.minX, current.minX)
    }

    func testOversizedContentIsBoundedByAvailableScreenBelowAnchor() {
        let current = CGRect(x: -1000, y: -500, width: 370, height: 450)
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let resized = MenuPopoverGeometry.frame(
            size: CGSize(width: 2300, height: 2000), anchoredTo: current, visibleFrame: visible
        )

        XCTAssertTrue(visible.contains(resized))
        XCTAssertEqual(resized.width, visible.width)
        XCTAssertEqual(resized.minY, visible.minY)
        XCTAssertEqual(resized.maxY, current.maxY)
    }

    @MainActor
    func testMenuViewFittingSize() {
        let host = NSHostingView(rootView: MenuView().environmentObject(AppState.shared))
        XCTAssertGreaterThan(host.fittingSize.height, 400)
        XCTAssertEqual(host.fittingSize.width, 370)
    }
}
