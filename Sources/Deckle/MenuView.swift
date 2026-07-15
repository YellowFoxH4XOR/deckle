import SwiftUI
import ServiceManagement

/// Content of the menu bar popover: master toggle, intensity slider,
/// sectioned texture picker, snooze controls, per-display toggles, footer.
struct MenuView: View {
    @EnvironmentObject private var state: AppState
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
            snoozeSection
            if NSScreen.screens.count > 1 {
                Divider()
                displaysSection
            }
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
            }
            .padding(.vertical, 2)
        }
        .frame(height: 264)
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Text("⌥⌘P toggles the texture from anywhere")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
