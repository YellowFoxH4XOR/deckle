import SwiftUI
import AppKit

/// Modern, elevated menu bar popover for Deckle.
/// Features direct Paper Mill opening, search field, prominent hero status card,
/// feature spotlight card, preset carousel/grid with scroll affordances, and expandable fine-tuning drawer.
struct MenuView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = UpdateManager.shared
    @State private var searchText = ""
    @State private var isShowingAllPapers = false
    @ObservedObject private var mill = PaperMill.shared
    @State private var isDetailsExpanded = false
    @State private var showNotificationSheet = false
    @State private var dismissedUpdateVersion: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // 1. Top Navigation & Action Header (Always Pinned at Top)
            topHeaderBar

            // 2. Search Bar
            searchBar

            // 3. Update & Notification Banner
            if case .available(let version) = updater.status, dismissedUpdateVersion != version {
                updateBanner(version: version)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            } else if updater.status == .installing {
                installingBanner
            } else if showNotificationSheet {
                notificationBanner
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            if !isLibraryFocused {
                HeroCardView(isDetailsExpanded: $isDetailsExpanded)
            }

            // The header control must stay functional while search results are shown.
            if isDetailsExpanded {
                QuickControlsView(isExpanded: $isDetailsExpanded)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !isLibraryFocused && !isDetailsExpanded {
                FeaturePromoCard {
                    PaperMill.shared.open()
                }
            }

            // 7. Preset Carousel / Grid
            PresetCollectionView(
                searchText: $searchText,
                isShowingAllGrid: $isShowingAllPapers,
                onOpenMill: { paper, isNew in
                    if isNew {
                        PaperMill.shared.compose(from: paper)
                    } else {
                        PaperMill.shared.open(editing: paper)
                    }
                }
            )

            // 8. Footer Info & Actions
            footer
        }
        .padding(14)
        .frame(width: 370)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isDetailsExpanded)
        .animation(.easeInOut(duration: 0.2), value: isSearching)
        .animation(.easeOut(duration: 0.2), value: isShowingAllPapers)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showNotificationSheet)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dismissedUpdateVersion)
        .onChange(of: isShowingAllPapers) { expanded in
            if expanded {
                isDetailsExpanded = false
                isSearchFocused = false
            }
        }
    }

    // MARK: - 1. Top Header Bar (Matching Reference Design)

    private var topHeaderBar: some View {
        HStack(spacing: 8) {
            // Capsule "Open Mill" / "Close Mill" button -> Toggles Paper Mill window
            Button(action: {
                PaperMill.shared.toggle()
            }) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(mill.isOpen ? Color.accentColor : Color.blue)
                            .frame(width: 22, height: 22)

                        Image(systemName: mill.isOpen ? "xmark" : "wand.and.stars")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                    }

                    Text(mill.isOpen ? "Close Mill" : "Open Mill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(mill.isOpen ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(mill.isOpen ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .help(mill.isOpen ? "Close Paper Mill" : "Open Paper Mill to craft custom paper textures")
            Spacer()

            // 1. Prominent Notification / Update Bell Button (Matching Reference)
            Button(action: {
                let opening = !showNotificationSheet
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if opening { dismissedUpdateVersion = nil }
                    showNotificationSheet = opening
                }
                if opening, updater.status != .checking, updater.status != .installing {
                    Task { await updater.check(userInitiated: true) }
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 36, height: 36)
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                        Image(systemName: showNotificationSheet || isUpdateAvailable ? "bell.fill" : "bell")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isUpdateAvailable ? Color.accentColor : Color.primary)
                    }
                    .overlay(
                        Circle()
                            .stroke(
                                isUpdateAvailable ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.12),
                                lineWidth: 1
                            )
                    )

                    // Active notification / update badge dot
                    if isUpdateAvailable {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isUpdateAvailable ? "Update Available" : "Notifications & Updates")

            // 2. Profile / Settings Button (Matching Reference)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isDetailsExpanded.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 36, height: 36)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isDetailsExpanded ? Color.accentColor : Color.primary)
                }
                .overlay(
                    Circle()
                        .stroke(isDetailsExpanded ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(isDetailsExpanded ? "Hide adjustments" : "Profile & Adjustments")
        }
    }

    private var isUpdateAvailable: Bool {
        if case .available = updater.status { return true }
        return false
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLibraryFocused: Bool {
        isSearching || isShowingAllPapers
    }

    // MARK: - 2. Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)

            TextField("Search all papers & textures…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onChange(of: isSearchFocused) { focused in
                    if focused {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSearchFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            isSearchFocused = true
        }
    }

    // MARK: - 3. Update & Notification Banners

    private func updateBanner(version: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Deckle \(version) is available")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                Text("New engine improvements ready.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: {
                updater.installLatest()
            }) {
                Text("Update")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 3, y: 1)
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dismissedUpdateVersion = version
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss notification")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.accentColor.opacity(0.08), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var installingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Installing update…")
                    .font(.system(size: 12, weight: .semibold))
                Text("Deckle will relaunch automatically.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var notificationBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(notificationColor.opacity(0.12))
                    .frame(width: 34, height: 34)

                Image(systemName: notificationSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(notificationColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(updaterStatusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Version \(updater.currentVersion) · Spectral Engine v2")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showNotificationSheet = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var updaterStatusText: String {
        switch updater.status {
        case .checking: return "Checking for updates…"
        case .upToDate: return "Deckle is up to date"
        case .available(let v): return "Version \(v) available"
        case .installing: return "Installing update…"
        case .failed(let err): return err
        case .idle: return "No new notifications"
        }
    }

    private var notificationSymbol: String {
        switch updater.status {
        case .checking: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.circle.fill"
        case .available: return "arrow.down.circle.fill"
        case .installing: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "bell.slash"
        }
    }

    private var notificationColor: Color {
        switch updater.status {
        case .failed: return .orange
        case .upToDate: return .green
        case .available, .checking, .installing: return .accentColor
        case .idle: return .secondary
        }
    }

    // MARK: - 8. Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 4) {
                Text("⌥⌘P")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("toggles anywhere")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 8) {
                Link("★ GitHub", destination: URL(string: "https://github.com/YellowFoxH4XOR/deckle")!)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
            }
        }
        .padding(.top, 2)
    }
}
