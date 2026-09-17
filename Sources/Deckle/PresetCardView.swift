import SwiftUI
import AppKit

/// Category filter options for browsing presets
enum PresetCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case light = "Light"
    case dark = "Dark"
    case custom = "My Papers"

    var id: String { rawValue }
}

/// A modern, tactile preset card for the carousel and grid.
struct ModernPresetCard: View {
    let preset: TexturePreset
    let isSelected: Bool
    var isCustom: Bool = false
    var customPaper: CustomPaper? = nil
    var onOpenMill: ((CustomPaper, Bool) -> Void)? = nil
    let action: () -> Void

    @EnvironmentObject private var state: AppState

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Top Preview Image
                ZStack(alignment: .topTrailing) {
                    PaperSample(preset: preset, size: CGSize(width: 92, height: 52))
                        .equatable()
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Selected checkmark or custom indicator
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(4)
                    }
                }

                // Text labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                        .lineLimit(1)

                    Text(tagText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .frame(width: 108)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? StudioStyle.rust.opacity(0.09) : Color(nsColor: .controlBackgroundColor).opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        isSelected ? StudioStyle.rust : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let customPaper {
                Button("Edit in Paper Mill…") {
                    if let onOpenMill {
                        onOpenMill(customPaper, false)
                    } else {
                        PaperMill.shared.open(editing: customPaper)
                    }
                }
                Button("Export Paper…") {
                    PaperFiles.export(customPaper)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    state.customPapers.removeAll { $0.id == customPaper.id }
                }
            } else {
                Button("Duplicate in Paper Mill…") {
                    let duplicate = CustomPaper(
                        name: "\(preset.name) Copy",
                        tintRed: Double(preset.tint.redComponent),
                        tintGreen: Double(preset.tint.greenComponent),
                        tintBlue: Double(preset.tint.blueComponent),
                        wash: Double(preset.tintAlpha),
                        weave: Double(preset.weave?.amplitude ?? 0),
                        blotch: Double(preset.octaves.first(where: { $0.cell == 16 })?.weight ?? 0),
                        engineVersion: preset.engineVersion,
                        seed: preset.seed,
                        fiberAngle: preset.v3Config?.fiberAngle ?? 0.3,
                        fiberStrength: preset.v3Config?.fiberStrength ?? 0.30,
                        surfaceRoughness: preset.v3Config?.surfaceRoughness ?? 0.15,
                        darkGrainStrength: preset.darkStrength,
                        lightGrainStrength: preset.lightStrength
                    )
                    if let onOpenMill {
                        onOpenMill(duplicate, true)
                    } else {
                        PaperMill.shared.compose(from: duplicate)
                    }
                }
            }
        }
        .help(preset.subtitle)
    }

    private var tagText: String {
        if isCustom {
            return "Custom"
        } else if preset.isQuietReading {
            return preset.id == "clear-veil" ? "No grain" : "Quiet reading"
        } else if preset.isDark {
            return "Dark paper"
        } else if preset.weave != nil {
            return "Woven"
        } else {
            return preset.subtitle.components(separatedBy: ",").first ?? "Smooth"
        }
    }
}

/// Collection section containing the preset carousel or full multi-column grid,
/// with search filtering, category tabs, and clear scroll affordances (floating arrows and edge fades).
struct PresetCollectionView: View {
    @EnvironmentObject private var state: AppState
    @Binding var searchText: String
    @Binding var isShowingAllGrid: Bool
    var onOpenMill: ((CustomPaper, Bool) -> Void)? = nil
    @State private var selectedCategory: PresetCategory = .all
    @State private var scrollIndex: Int = 0

    private var normalizedQuery: String {
        PaperSearch.normalized(searchText)
    }

    private var isSearching: Bool { !normalizedQuery.isEmpty }

    private func gridViewportHeight(presetCount: Int) -> CGFloat {
        let rowCount = max(1, (presetCount + 2) / 3)
        let cardHeight: CGFloat = 108
        let rowSpacing: CGFloat = 8
        let contentHeight = CGFloat(rowCount) * cardHeight
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
            + 4
        return min(isSearching ? 360 : 356, max(cardHeight + 4, contentHeight))
    }

    private var filteredPresets: [TexturePreset] {
        let customPresets = state.customPapers.map { TexturePreset(custom: $0) }

        if isSearching {
            let customIDs = Set(state.customPapers.map(\.id))
            return (TexturePreset.all + customPresets).filter { preset in
                PaperSearch.matches(preset, query: normalizedQuery, isCustom: customIDs.contains(preset.id))
            }
        }

        switch selectedCategory {
        case .all:
            return TexturePreset.all + customPresets
        case .light:
            return TexturePreset.light + customPresets.filter { !$0.isDark }
        case .dark:
            return TexturePreset.dark + customPresets.filter(\.isDark)
        case .custom:
            return customPresets
        }
    }

    var body: some View {
        let presets = filteredPresets
        let customPapersByID = Dictionary(
            state.customPapers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        content(presets: presets, customPapersByID: customPapersByID)
    }

    @ViewBuilder
    private func content(presets: [TexturePreset], customPapersByID: [String: CustomPaper]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: "Presets" on left, "All papers >" toggle on right
            // Header Row
            HStack {
                HStack(spacing: 6) {
                    if isSearching {
                        Text("Search Results")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("\(presets.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(StudioStyle.rust)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(StudioStyle.rust.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Text(isShowingAllGrid ? "Paper library" : "Paper samples")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)

                        if !isShowingAllGrid && presets.count > 2 {
                            Text("\(presets.count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                if isSearching {
                    Button("Clear") {
                        searchText = ""
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StudioStyle.rust)
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        let expanding = !isShowingAllGrid
                        isShowingAllGrid = expanding
                        if !expanding { selectedCategory = .all }
                    }) {
                        HStack(spacing: 4) {
                            Text(isShowingAllGrid ? "Your desk" : "All papers")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: isShowingAllGrid ? "chevron.up" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(StudioStyle.rust)
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button("New Paper…") {
                        if let onOpenMill {
                            onOpenMill(CustomPaper(), true)
                        } else {
                            PaperMill.shared.open()
                        }
                    }
                    Button("Import Papers…") { PaperFiles.importPapers() }
                    Button("Community Papers…") { CommunityBrowser.shared.open() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Paper actions")
            }

            // Category Filter Pills (when in All Grid or searching)
            if isShowingAllGrid && !isSearching {
                HStack(spacing: 6) {
                    ForEach(PresetCategory.allCases) { category in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCategory = category
                                scrollIndex = 0
                            }
                        }) {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: selectedCategory == category ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedCategory == category ? StudioStyle.rust : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Quick New Paper Button
                    Button(action: {
                        if let onOpenMill {
                            onOpenMill(CustomPaper(), true)
                        } else {
                            PaperMill.shared.open()
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .padding(5)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Create new custom paper")
                }
            }

            // Carousel or Grid Content
            if presets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(isSearching ? "No papers matching \"\(normalizedQuery)\"" : "No papers found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if isSearching {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .controlSize(.small)
                    } else if selectedCategory == .custom {
                        Button("Create custom paper") {
                            if let onOpenMill {
                                onOpenMill(CustomPaper(), true)
                            } else {
                                PaperMill.shared.open()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
            } else if isShowingAllGrid || isSearching {
                // Multi-Column Grid
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(presets) { preset in
                            let custom = customPapersByID[preset.id]
                            ModernPresetCard(
                                preset: preset,
                                isSelected: preset.id == state.textureID,
                                isCustom: custom != nil,
                                customPaper: custom,
                                onOpenMill: onOpenMill
                            ) {
                                state.isComparingOriginal = false
                                state.textureID = preset.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: gridViewportHeight(presetCount: presets.count))
                .layoutPriority(1)
            } else {
                // Horizontal Carousel with Interactive Scroll Affordance
                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        // Horizontal Scroll View
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                                    let custom = customPapersByID[preset.id]
                                    ModernPresetCard(
                                        preset: preset,
                                        isSelected: preset.id == state.textureID,
                                        isCustom: custom != nil,
                                        customPaper: custom,
                                        onOpenMill: onOpenMill
                                    ) {
                                        state.isComparingOriginal = false
                                        state.textureID = preset.id
                                    }
                                    .id(index)
                                }
                            }
                            .padding(.leading, 1)
                            .padding(.trailing, 28) // Extra padding for the floating chevron
                            .padding(.vertical, 2)
                        }

                        // A fade is useful only when three cards exceed the viewport.
                        if presets.count > 2 {
                            HStack {
                                Spacer()
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .windowBackgroundColor).opacity(0),
                                        Color(nsColor: .windowBackgroundColor).opacity(0.85)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 32)
                                .allowsHitTesting(false)
                            }
                        }

                        // Floating Circular Scroll Next Button (matching reference)
                        if presets.count > 2 {
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    scrollIndex = (scrollIndex + 2) % presets.count
                                    proxy.scrollTo(scrollIndex, anchor: .leading)
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .frame(width: 28, height: 28)
                                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.primary.opacity(0.8))
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .offset(x: -2)
                            .help("Scroll more papers")
                        }
                    }
                }
            }
        }
    }
}
