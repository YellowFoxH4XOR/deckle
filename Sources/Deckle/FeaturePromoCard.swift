import SwiftUI
import AppKit

/// Rotating feature card for discoverable actions without nested controls.
struct FeaturePromoCard: View {
    var onOpenMill: (() -> Void)? = nil
    @AppStorage("dismissedPaperMillTip") private var isDismissed = false
    @State private var currentTipIndex = 0

    private struct PromoTip {
        let icon: String
        let iconColor: Color
        let iconBackground: Color
        let title: String
        let description: String
        let action: () -> Void
    }

    private var tips: [PromoTip] {
        [
            PromoTip(
                icon: "wand.and.stars",
                iconColor: .purple,
                iconBackground: Color.purple.opacity(0.12),
                title: "Blend custom paper in Paper Mill",
                description: "Mix custom washes, woven fibers, and organic blotches to make a tactile texture.",
                action: {
                    if let onOpenMill {
                        onOpenMill()
                    } else {
                        PaperMill.shared.open()
                    }
                }
            ),
            PromoTip(
                icon: "globe.americas.fill",
                iconColor: .blue,
                iconBackground: Color.blue.opacity(0.12),
                title: "Explore community papers",
                description: "Browse and install handcrafted paper textures from the open-source community.",
                action: { CommunityBrowser.shared.open() }
            )
        ]
    }

    var body: some View {
        if !isDismissed {
            let tip = tips[currentTipIndex % tips.count]

            HStack(alignment: .top, spacing: 8) {
                Button(action: tip.action) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(tip.iconBackground)
                                .frame(width: 38, height: 38)

                            Image(systemName: tip.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(tip.iconColor)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(tip.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(tip.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss tip")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentTipIndex = (currentTipIndex + 1) % tips.count
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Next tip")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}
