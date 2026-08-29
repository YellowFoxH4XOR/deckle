import SwiftUI
import AppKit

/// Prominent hero card displaying current texture status, preview avatar,
/// master toggle pill button, and quick intensity slider.
struct HeroCardView: View {
    @EnvironmentObject private var state: AppState
    @Binding var isDetailsExpanded: Bool

    private var displayCount: Int {
        NSScreen.screens.count
    }

    private var activeDisplaysSummary: String {
        let active = NSScreen.screens.compactMap { $0.displayID }.filter { !state.excludedDisplays.contains(String($0)) }
        if active.count == displayCount {
            return displayCount == 1 ? "1 DISPLAY" : "\(displayCount) DISPLAYS"
        } else {
            return "\(active.count)/\(displayCount) ACTIVE"
        }
    }

    private var metaLine: String {
        let statusString: String
        if state.isSnoozed {
            statusString = "SNOOZED"
        } else if state.isEnabled {
            statusString = "ACTIVE"
        } else {
            statusString = "PAUSED"
        }
        return "ENGINE V2 • \(activeDisplaysSummary) • \(statusString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Meta header row
            HStack {
                Text(metaLine)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.isSnoozed, let until = state.snoozeUntil {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(timerInterval: Date()...until, countsDown: true)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.orange)
                }
            }

            // Main identity row
            HStack(spacing: 14) {
                // Circular texture swatch
                ZStack {
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 50, height: 50)
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)

                    Image(nsImage: TextureRenderer.preview(
                        for: state.texture,
                        size: CGSize(width: 50, height: 50)
                    ))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                state.shouldShowOverlay ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12),
                                lineWidth: 1.5
                            )
                    )
                }

                // Texture name & status text
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.texture.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: statusColor.opacity(0.5), radius: 3, x: 0, y: 0)

                        Text(statusLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(statusColor)
                    }
                }

                Spacer()
            }

            // Primary action button & options button
            HStack(spacing: 10) {
                // Main toggle pill button
                Button(action: toggleOverlay) {
                    HStack(spacing: 8) {
                        Image(systemName: mainButtonIcon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mainButtonTitle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(mainButtonBackground)
                    .foregroundStyle(mainButtonForeground)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(mainButtonBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                }
                .buttonStyle(.plain)

                // Secondary "..." options button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isDetailsExpanded.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)

                        Image(systemName: isDetailsExpanded ? "slider.horizontal.3" : "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isDetailsExpanded ? Color.accentColor : Color.primary.opacity(0.75))
                    }
                    .overlay(
                        Circle()
                            .stroke(isDetailsExpanded ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(isDetailsExpanded ? "Hide adjustments" : "Adjust grain & fine-tuning")
            }

            // Inline Intensity Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label {
                        Text("Intensity")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "sun.min")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(Int(state.intensity * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Slider(value: $state.intensity, in: 0.05...0.45)
                    .tint(.accentColor)
                    .disabled(!state.isEnabled)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Helper properties & actions

    private var statusColor: Color {
        if state.isSnoozed {
            return .orange
        } else if state.isEnabled {
            return Color(nsColor: .systemGreen)
        } else {
            return .secondary
        }
    }

    private var statusLabel: String {
        if state.isSnoozed {
            return "Snoozed"
        } else if state.isEnabled {
            return "Active"
        } else {
            return "Paused"
        }
    }

    private var mainButtonTitle: String {
        if state.isSnoozed {
            return "Resume texture"
        } else if state.isEnabled {
            return "Pause texture"
        } else {
            return "Enable texture"
        }
    }

    private var mainButtonIcon: String {
        if state.isSnoozed {
            return "play.fill"
        } else if state.isEnabled {
            return "pause.fill"
        } else {
            return "power"
        }
    }

    private var mainButtonBackground: Color {
        if state.isSnoozed || !state.isEnabled {
            return Color.accentColor
        } else {
            return Color(nsColor: .windowBackgroundColor)
        }
    }

    private var mainButtonForeground: Color {
        if state.isSnoozed || !state.isEnabled {
            return .white
        } else {
            return .primary
        }
    }

    private var mainButtonBorder: Color {
        if state.isSnoozed || !state.isEnabled {
            return Color.accentColor.opacity(0.8)
        } else {
            return Color.primary.opacity(0.12)
        }
    }

    private func toggleOverlay() {
        if state.isSnoozed {
            state.cancelSnooze()
            state.isEnabled = true
        } else if state.isEnabled {
            state.isEnabled = false
        } else {
            state.isEnabled = true
        }
    }
}
