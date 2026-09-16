import SwiftUI
import AppKit

/// The selected paper is the main surface, like a labelled sample on a desk.
struct HeroCardView: View {
    @EnvironmentObject private var state: AppState

    private var ink: Color { state.texture.isDark ? .white : Color(red: 0.16, green: 0.14, blue: 0.11) }
    private var status: String {
        if state.isComparingOriginal { return "Comparing · bare screen" }
        if state.previewPaper != nil { return "Paper Mill draft on screen" }
        if state.isSnoozed { return "Snoozed" }
        return state.isEnabled ? "Enabled · follows your app rules" : "Paused"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                PaperSample(preset: state.texture, size: CGSize(width: 342, height: 148))
                    .equatable()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(state.texture.isQuietReading ? "PAPER SAMPLE · 22%" : "ON YOUR DESK")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.8)
                        Spacer()
                        Image(systemName: "leaf")
                    }
                    Spacer()
                    Text(state.texture.name)
                        .font(.system(size: 27, weight: .medium, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(state.texture.subtitle)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                .foregroundStyle(ink)
                .padding(16)
            }
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12)))

            HStack(spacing: 6) {
                Circle().fill(state.shouldShowOverlay && !state.isComparingOriginal ? StudioStyle.rust : .secondary)
                    .frame(width: 5, height: 5)
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack {
                Text("Paper intensity").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(state.intensity * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $state.intensity, in: 0.05...0.45)
                .accessibilityLabel("Paper intensity")

            HStack {
                Text("Matte finish").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int((state.matteStrength * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $state.matteStrength, in: 0...1)
                .tint(StudioStyle.rust)
                .accessibilityLabel("Matte finish")
                .accessibilityValue("\(Int((state.matteStrength * 100).rounded())) percent")

            HStack(spacing: 8) {
                Button {
                    state.isComparingOriginal = false
                    if state.shouldShowOverlay { state.isEnabled = false }
                    else { state.cancelSnooze(); state.isEnabled = true }
                } label: {
                    Label(state.shouldShowOverlay ? "Pause paper" : "Enable paper",
                          systemImage: state.shouldShowOverlay ? "pause" : "play")
                        .frame(maxWidth: .infinity)
                }
                .disabled(state.previewPaper != nil)
                Button {
                    state.isComparingOriginal.toggle()
                } label: {
                    Label(state.isComparingOriginal ? "Back to paper" : "Compare original",
                          systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!state.shouldShowOverlay && state.previewPaper == nil && !state.isComparingOriginal)
                .help("Temporarily hide the paper. Closing the menu restores it.")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 11))
        }
    }
}
