import XCTest
import SwiftUI
@testable import Deckle

final class ReadingProofTests: XCTestCase {
    @MainActor
    func testRenderReadingProof() throws {
        guard let directory = ProcessInfo.processInfo.environment["DECKLE_RENDER_DIR"] else { throw XCTSkip("Opt-in reading proof") }
        for dark in [false, true] {
            let samples: [TexturePreset?] = [nil, TexturePreset.preset(id: "classic-matte")] + TexturePreset.readingCollection.map(Optional.some)
            let view = VStack(alignment: .leading, spacing: 18) {
                Text("Quiet papers, real text.").font(.system(size: 28, weight: .medium, design: .serif))
                Text("Production overlays at 22% intensity · 1× grain size · 1× strength")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                VStack(spacing: 18) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<2, id: \.self) { column in
                                let preset = samples[row * 2 + column]
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(preset?.name ?? "Bare screen")
                                        .font(.system(size: 14, weight: .semibold))
                                    ZStack(alignment: .topLeading) {
                                        Color(white: dark ? 0.1333 : 1)
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("A little room to think.")
                                                .font(.system(size: 21, weight: .medium, design: .serif))
                                                .foregroundStyle(Color(white: dark ? 0.92 : 0.2))
                                            Text("Read at your own pace. Keep the words clear and the background quiet.")
                                                .font(.system(size: 14))
                                                .lineSpacing(5)
                                                .foregroundStyle(Color(white: dark ? 0.8 : 0.42))
                                            Text("Small details should stay legible.")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color(white: dark ? 0.8 : 0.42))
                                        }.padding(20)
                                        if let preset {
                                            Image(nsImage: TextureRenderer.compositeTile(for: preset, backingScale: 1))
                                                .resizable(resizingMode: .tile)
                                                .opacity(0.22)
                                        }
                                    }
                                    .frame(width: 340, height: 190)
                                    .clipped()
                                    .overlay(Rectangle().stroke(Color.primary.opacity(0.12)))
                                }
                            }
                        }
                    }
                }
                Text("These samples demonstrate appearance, not a medical benefit. Actual comfort depends on your display, room and vision.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(24).frame(width: 748)
            .background(Color(white: 0.965))
            .environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(dark ? "reading-proof-dark.png" : "reading-proof-light.png"))
        }
    }
}
