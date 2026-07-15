import SwiftUI
import ServiceManagement

/// Content of the menu bar popover: master toggle, intensity slider,
/// sectioned texture picker, snooze controls, per-display toggles, footer.
struct MenuView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = UpdateManager.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            intensitySection
            Divider()
            textureSections
            Divider()
            grainSection
            Divider()
            snoozeSection
            if NSScreen.screens.count > 1 {
                Divider()
                displaysSection
            }
            Divider()
            appRulesSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 336)
    }

    private var statusText: String {
        if state.isSnoozed { return "Snoozed" }
        if !state.isEnabled { return "Off" }
        return "\(state.texture.name) · \(Int(state.intensity * 100))%"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Deckle")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $state.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Toggle from anywhere with ⌥⌘P")
        }
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Intensity")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(state.intensity * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $state.intensity, in: 0.05...0.45)
        }
        .disabled(!state.isEnabled)
    }

    private var textureSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                textureGroup(title: "Papers", presets: TexturePreset.light)
                textureGroup(title: "Dark", presets: TexturePreset.dark)
                myPapersGroup
            }
            .padding(.vertical, 2)
        }
        .frame(height: 264)
    }

    private var myPapersGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("My Papers")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("New…") { PaperMill.shared.open() }
                    .controlSize(.mini)
                Button("Import…") { PaperFiles.importPapers() }
                    .controlSize(.mini)
                Button("Community…") { CommunityBrowser.shared.open() }
                    .controlSize(.mini)
            }
            if !state.customPapers.isEmpty {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(state.customPapers) { paper in
                        TextureSwatch(
                            preset: TexturePreset(custom: paper),
                            isSelected: paper.id == state.textureID
                        ) {
                            state.textureID = paper.id
                        }
                        .contextMenu {
                            Button("Edit…") { PaperMill.shared.open(editing: paper) }
                            Button("Export…") { PaperFiles.export(paper) }
                            Divider()
                            Button("Delete", role: .destructive) {
                                state.customPapers.removeAll { $0.id == paper.id }
                            }
                        }
                    }
                }
            } else {
                Text("Blend your own paper in the Mill — tint, wash, weave, blotch.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func textureGroup(title: String, presets: [TexturePreset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(presets) { preset in
                    TextureSwatch(
                        preset: preset,
                        isSelected: preset.id == state.textureID
                    ) {
                        state.textureID = preset.id
                    }
                }
            }
        }
    }

    private var grainSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Grain")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $state.grainScale) {
                    Text("Fine").tag(0.5)
                    Text("Normal").tag(1.0)
                    Text("Coarse").tag(2.0)
                    Text("Grainy").tag(4.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            HStack {
                Text("Strength")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $state.grainStrength, in: 0.25...2.0)
                Text("\(Int(state.grainStrength * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .disabled(!state.isEnabled)
    }

    private var snoozeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.isSnoozed, let until = state.snoozeUntil {
                HStack {
                    Text("Snoozed for ")
                        .font(.subheadline)
                    + Text(timerInterval: Date()...until, countsDown: true)
                        .font(.subheadline)
                        .monospacedDigit()
                    Spacer()
                    Button("Resume") { state.cancelSnooze() }
                        .controlSize(.small)
                }
            } else {
                HStack {
                    Text("Snooze")
                        .font(.subheadline)
                    Spacer()
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button(minutes == 60 ? "1 h" : "\(minutes) m") {
                            state.snooze(minutes: minutes)
                        }
                        .controlSize(.small)
                    }
                }
                .disabled(!state.isEnabled)
            }
        }
    }

    private var displaysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Displays")
                .font(.subheadline)
            ForEach(NSScreen.screens, id: \.self) { screen in
                if let displayID = screen.displayID {
                    Toggle(screen.localizedName, isOn: displayBinding(String(displayID)))
                        .toggleStyle(.checkbox)
                        .font(.caption)
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

    @State private var appRulesExpanded = false

    private var appRulesSection: some View {
        DisclosureGroup(isExpanded: $appRulesExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $state.appRuleMode) {
                    Text("Everywhere").tag(AppState.AppRuleMode.everywhere)
                    Text("Except…").tag(AppState.AppRuleMode.except)
                    Text("Only…").tag(AppState.AppRuleMode.only)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if state.appRuleMode != .everywhere {
                    ForEach(state.ruleApps) { app in
                        HStack {
                            Text(app.name)
                                .font(.caption)
                            Spacer()
                            Button {
                                state.ruleApps.removeAll { $0.bundleID == app.bundleID }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add App…") { addRuleApp() }
                        .controlSize(.small)
                    Text(state.appRuleMode == .except
                         ? "Paper hides while these apps are active"
                         : "Paper shows only while these apps are active")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Text("App rules")
                    .font(.subheadline)
                if state.appRuleMode != .everywhere {
                    Text(state.appRuleMode == .except ? "except \(state.ruleApps.count)" : "only \(state.ruleApps.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            updateRow
            Toggle("Hide texture in screenshots & recordings", isOn: $state.hideFromCapture)
                .toggleStyle(.checkbox)
                .font(.caption)
            HStack {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(!isBundled)
                    .help(isBundled ? "" : "Available when running the bundled app")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
            HStack {
                Toggle("Install updates automatically", isOn: $updater.autoInstall)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Check now") {
                    Task { await updater.check(userInitiated: true) }
                }
                .controlSize(.small)
                .disabled(updater.status == .checking || updater.status == .installing)
            }
            Text("v\(updater.currentVersion) · ⌥⌘P toggles the texture from anywhere")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updater.status {
        case .available(let version):
            HStack {
                Text("Deckle \(version) is available")
                    .font(.caption)
                Spacer()
                Button("Update") { updater.installLatest() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing update — Deckle will relaunch…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .checking:
            Text("Checking for updates…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate:
            Text("You're on the latest version")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
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

/// One tappable texture thumbnail in the picker grid.
private struct TextureSwatch: View {
    let preset: TexturePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: TextureRenderer.preview(
                    for: preset,
                    size: CGSize(width: 88, height: 44)
                ))
                .resizable()
                .aspectRatio(2, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                Text(preset.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(preset.subtitle)
    }
}
