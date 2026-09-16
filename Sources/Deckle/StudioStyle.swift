import SwiftUI

/// A restrained stationery palette; secondary windows still use native controls.
enum StudioStyle {
    static let rust = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.90, green: 0.57, blue: 0.39, alpha: 1)
            : NSColor(srgbRed: 0.70, green: 0.29, blue: 0.13, alpha: 1)
    })
}

/// Isolates spectral thumbnail work from unrelated UI state changes.
struct PaperSample: View, Equatable {
    let preset: TexturePreset
    let size: CGSize

    var body: some View {
        Group {
            if preset.isQuietReading {
                // Quiet swatches use actual overlay strength, never boosted grain.
                ZStack {
                    Color(nsColor: preset.isDark
                          ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1) : .white)
                    Image(nsImage: TextureRenderer.compositeTile(for: preset, backingScale: 1))
                        .resizable(resizingMode: .tile)
                        .opacity(0.22)
                }
            } else {
                Image(nsImage: TextureRenderer.preview(for: preset, size: size))
                    .resizable()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }
}
