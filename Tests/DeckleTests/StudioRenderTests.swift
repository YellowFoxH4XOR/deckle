import XCTest
import SwiftUI
@testable import Deckle

final class StudioRenderTests: XCTestCase {
    @MainActor
    func testRenderStudioForReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["DECKLE_RENDER_DIR"] else { throw XCTSkip("Opt-in review renders") }
        let suite = "DeckleStudioRender"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults)
        for (name, scheme) in [("studio-desk", ColorScheme.light), ("studio-desk-dark", ColorScheme.dark)] {
            let view = MenuView().environmentObject(state).environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        let library = PresetCollectionView(searchText: .constant(""), isShowingAllGrid: .constant(true))
            .environmentObject(state).padding(14).frame(width: 370)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: library)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("studio-library.png"))
    }
}
