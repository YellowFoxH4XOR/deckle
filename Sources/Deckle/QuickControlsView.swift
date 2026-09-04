import SwiftUI
import AppKit
import ServiceManagement

/// Expandable fine-tuning panel for Grain parameters, Snooze timer,
/// Multi-Display toggles, App Rules, and Preferences.
struct QuickControlsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = UpdateManager.shared
    @Binding var isExpanded: Bool
    @Binding var selectedTab: ControlTab
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    enum ControlTab: String, CaseIterable, Identifiable {
        case grain = "Grain"
        case snooze = "Snooze"
        case displays = "Displays"
        case appRules = "App Rules"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .grain: return "slider.horizontal.2.square"
            case .snooze: return "moon.stars.fill"
            case .displays: return "display.2"
            case .appRules: return "app.badge.checkmark"
            case .settings: return "gearshape"
            }
        }
    }

    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row with Title and Close Button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: selectedTab.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(selectedTab == .settings ? "Settings & Preferences" : "Fine-Tuning & Controls")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close controls")
            }
            .padding(.horizontal, 2)

            // Horizontally scrollable Tab Pills with Scroll Fade Affordance
            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ControlTab.allCases) { tab in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTab = tab
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 11))
                                    Text(tab.rawValue)
                                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            selectedTab == tab ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.04),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 1)
                    .padding(.trailing, 16)
                    .padding(.vertical, 2)
                }

                // Right edge subtle fade
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0),
                        Color(nsColor: .windowBackgroundColor).opacity(0.9)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 20)
                .allowsHitTesting(false)
            }

            // Tab Content Card
            VStack(alignment: .leading, spacing: 12) {
                switch selectedTab {
                case .grain:
                    grainControls
                case .snooze:
                    snoozeControls
                case .displays:
                    displaysControls
                case .appRules:
                    appRulesControls
                case .settings:
                    settingsControls
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Grain Controls

    private var grainControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Scale Segmented Picker
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Grain Scale")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(grainScaleLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Picker("", selection: $state.grainScale) {
                    Text("Fine").tag(0.5)
                    Text("Normal").tag(1.0)
                    Text("Coarse").tag(2.0)
                    Text("Grainy").tag(4.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // Strength Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Grain Visibility")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(Int(state.grainStrength * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Slider(value: $state.grainStrength, in: 0.25...2.0)
                    .tint(.accentColor)
            }
        }
        .disabled(!state.isEnabled)
    }

    private var grainScaleLabel: String {
        switch state.grainScale {
        case 0.5: return "0.5× (Fine)"
        case 1.0: return "1.0× (Standard)"
        case 2.0: return "2.0× (Coarse)"
        case 4.0: return "4.0× (Heavy)"
        default: return String(format: "%.1f×", state.grainScale)
        }
    }

    // MARK: - Snooze Controls

    private var snoozeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isSnoozed, let until = state.snoozeUntil {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Currently Snoozed")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.orange)
                        HStack(spacing: 4) {
                            Text("Resuming in")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(timerInterval: Date()...until, countsDown: true)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Spacer()

                    Button("Resume Now") {
                        state.cancelSnooze()
                        state.isEnabled = true
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temporarily hide overlay:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach([15, 30, 60, 120], id: \.self) { minutes in
                            Button(action: { state.snooze(minutes: minutes) }) {
                                Text(minutes >= 120
                                     ? "\(minutes / 60) hours"
                                     : (minutes >= 60 ? "\(minutes / 60) hour" : "\(minutes) min"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .disabled(!state.isEnabled)
            }
        }
    }

    // MARK: - Display Controls

    private var displaysControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Displays")
                .font(.system(size: 12, weight: .semibold))

            ForEach(NSScreen.screens, id: \.self) { screen in
                if let displayID = screen.displayID {
                    HStack {
                        Image(systemName: "display")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        Toggle(screen.localizedName, isOn: displayBinding(String(displayID)))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func displayBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !state.excludedDisplays.contains(id) },
            set: { include in
                if include {
                    state.excludedDisplays.remove(id)
                } else {
                    state.excludedDisplays.insert(id)
                }
            }
        )
    }

    // MARK: - App Rules Controls

    private var appRulesControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $state.appRuleMode) {
                Text("Everywhere").tag(AppState.AppRuleMode.everywhere)
                Text("Except…").tag(AppState.AppRuleMode.except)
                Text("Only…").tag(AppState.AppRuleMode.only)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if state.appRuleMode != .everywhere {
                if state.ruleApps.isEmpty {
                    Text("No applications configured yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(state.ruleApps) { app in
                                HStack {
                                    Text(app.name)
                                        .font(.system(size: 11))
                                    Spacer()
                                    Button {
                                        state.ruleApps.removeAll { $0.bundleID == app.bundleID }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }

                HStack {
                    Button("Add App…") { addRuleApp() }
                        .controlSize(.small)

                    Spacer()

                    Text(state.appRuleMode == .except
                         ? "Hides in listed apps"
                         : "Shows only in listed apps")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(!state.isEnabled)
    }

    private func addRuleApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps for the rule list"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            if !state.ruleApps.contains(where: { $0.bundleID == id }) {
                state.ruleApps.append(.init(bundleID: id, name: name))
            }
        }
    }

    // MARK: - Settings Controls

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // App version and update status row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deckle v\(updater.currentVersion)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text("Spectral Engine v2 · macOS 13+")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                updateStatusBadge
            }
            .padding(.bottom, 2)

            Divider()

            Toggle("Hide in screenshots & screen recordings", isOn: $state.hideFromCapture)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Toggle("Launch automatically at login", isOn: launchAtLoginBinding)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .disabled(!isBundled)

            Toggle("Install updates automatically", isOn: $updater.autoInstall)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Divider()

            HStack {
                Button(action: {
                    if case .available = updater.status {
                        updater.installLatest()
                    } else {
                        Task { await updater.check(userInitiated: true) }
                    }
                }) {
                    HStack(spacing: 5) {
                        if updater.status == .checking || updater.status == .installing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(updateButtonTitle)
                    }
                }
                .controlSize(.small)
                .disabled(updater.status == .checking || updater.status == .installing)

                Spacer()

                Button("Quit Deckle") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var updateStatusBadge: some View {
        switch updater.status {
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Checking…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Up to date")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10, weight: .medium))
        case .available(let version):
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("v\(version) ready")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.system(size: 10, weight: .bold))
        case .installing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Installing…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        case .failed:
            Text("Check failed")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    private var updateButtonTitle: String {
        switch updater.status {
        case .checking: return "Checking…"
        case .installing: return "Installing…"
        case .available: return "Install Update"
        case .upToDate: return "Check Again"
        case .failed: return "Retry Check"
        case .idle: return "Check for Updates"
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = enable
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }
}
