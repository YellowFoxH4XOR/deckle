import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A user-created paper: a tiny recipe the procedural engine renders exactly
/// like a built-in preset. Values are clamped on conversion so imported
/// files can't produce anything outside the app's visual range.
struct CustomPaper: Codable, Equatable, Identifiable {
    var id: String = "custom-\(UUID().uuidString.lowercased())"
    var name: String = "My Paper"
    var tintRed: Double = 0.96
    var tintGreen: Double = 0.94
    var tintBlue: Double = 0.90
    /// Tint wash opacity at full design strength.
    var wash: Double = 0.38
    /// Woven crosshatch amount; 0 disables the weave.
    var weave: Double = 0
    /// Coarse mottling mixed into the grain.
    var blotch: Double = 0
    /// Procedural engine used to render this paper. Freshly created papers
    /// use the v2 spectral engine; papers saved before this field existed
    /// decode as `.legacy` so they keep rendering with the original
    /// generator, unchanged.
    var engineVersion: TextureEngineVersion = .spectral
    /// Stable per-paper RNG seed. Generated once when the paper is created
    /// and stored from then on (it round-trips through export/import)
    /// rather than being recomputed on every render.
    var seed: UInt64 = .random(in: .min ... .max)

    var isDark: Bool {
        0.299 * tintRed + 0.587 * tintGreen + 0.114 * tintBlue < 0.5
    }

    init(
        id: String = "custom-\(UUID().uuidString.lowercased())",
        name: String = "My Paper",
        tintRed: Double = 0.96,
        tintGreen: Double = 0.94,
        tintBlue: Double = 0.90,
        wash: Double = 0.38,
        weave: Double = 0,
        blotch: Double = 0,
        engineVersion: TextureEngineVersion = .spectral,
        seed: UInt64 = .random(in: .min ... .max)
    ) {
        self.id = id
        self.name = name
        self.tintRed = tintRed
        self.tintGreen = tintGreen
        self.tintBlue = tintBlue
        self.wash = wash
        self.weave = weave
        self.blotch = blotch
        self.engineVersion = engineVersion
        self.seed = seed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tintRed, tintGreen, tintBlue, wash, weave, blotch, engineVersion, seed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tintRed = try container.decode(Double.self, forKey: .tintRed)
        tintGreen = try container.decode(Double.self, forKey: .tintGreen)
        tintBlue = try container.decode(Double.self, forKey: .tintBlue)
        wash = try container.decode(Double.self, forKey: .wash)
        weave = try container.decode(Double.self, forKey: .weave)
        blotch = try container.decode(Double.self, forKey: .blotch)
        // Version-less saves predate the v2 engine: keep them on the
        // original generator so previously exported papers render unchanged.
        engineVersion = try container.decodeIfPresent(TextureEngineVersion.self, forKey: .engineVersion) ?? .legacy
        // Seed-less saves predate stored seeds: derive one deterministically
        // from the paper's id so re-imports keep reproducing the same grain.
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? CustomPaper.legacySeed(from: id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(tintRed, forKey: .tintRed)
        try container.encode(tintGreen, forKey: .tintGreen)
        try container.encode(tintBlue, forKey: .tintBlue)
        try container.encode(wash, forKey: .wash)
        try container.encode(weave, forKey: .weave)
        try container.encode(blotch, forKey: .blotch)
        try container.encode(engineVersion, forKey: .engineVersion)
        try container.encode(seed, forKey: .seed)
    }

    /// djb2 hash — deterministic across launches, so a legacy paper decoded
    /// without a stored seed always derives the same one from its id.
    private static func legacySeed(from id: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }
}

extension TexturePreset {
    /// Renders a custom paper through the same engine as built-ins: colors
    /// derive from the tint, blotch adds a coarse octave, weave adds the
    /// crosshatch. Every input is clamped — imports are untrusted.
    init(custom paper: CustomPaper) {
        func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
            min(max(v, range.lowerBound), range.upperBound)
        }
        let r = clamp(paper.tintRed, 0...1)
        let g = clamp(paper.tintGreen, 0...1)
        let b = clamp(paper.tintBlue, 0...1)
        let wash = clamp(paper.wash, 0.10...0.60)
        let weave = clamp(paper.weave, 0...0.35)
        let blotch = clamp(paper.blotch, 0...0.40)
        let dark = paper.isDark

        var octaves: [(cell: Int, weight: Float)] = [(1, 0.45), (2, 0.30), (4, 0.25)]
        if blotch > 0.01 {
            octaves.append((16, Float(blotch)))
        }

        self.init(
            id: paper.id,
            name: paper.name.isEmpty ? "My Paper" : paper.name,
            subtitle: "Custom paper",
            tint: NSColor(srgbRed: r, green: g, blue: b, alpha: 1),
            tintAlpha: wash,
            // Speckles: darkened tint for shadows, lightened for highlights —
            // keeps custom papers tonally coherent at any hue.
            darkColor: NSColor(srgbRed: r * 0.30, green: g * 0.28, blue: b * 0.25, alpha: 1),
            lightColor: NSColor(srgbRed: r + (1 - r) * 0.85, green: g + (1 - g) * 0.85, blue: b + (1 - b) * 0.85, alpha: 1),
            darkStrength: dark ? 0.30 : 0.50,
            lightStrength: dark ? 0.45 : 0.35,
            octaves: octaves,
            weave: weave > 0.01 ? (period: 8, amplitude: Float(weave)) : nil,
            isDark: dark,
            engineVersion: paper.engineVersion,
            seed: paper.seed
        )
    }
}

/// The Paper Mill: standalone editor window for creating and editing
/// custom papers, with live on-screen preview, eye-comfort readouts, and non-overlapping positioning.
@MainActor
final class PaperMill: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = PaperMill()
    @Published private(set) var isOpen: Bool = false
    private var window: NSWindow?

    func toggle(editing paper: CustomPaper? = nil) {
        if isOpen, window != nil {
            close()
        } else {
            open(editing: paper)
        }
    }

    func close() {
        AppState.shared.previewPaper = nil
        window?.close()
        window = nil
        isOpen = false
    }

    func open(editing paper: CustomPaper? = nil) {
        present(
            draft: paper ?? CustomPaper(),
            isNew: paper == nil,
            title: paper == nil ? "New Paper" : "Edit Paper"
        )
    }

    /// Opens the editor pre-filled with `paper` as a brand-new unsaved draft:
    /// a fresh id and seed, and nothing written to `customPapers` until the
    /// user hits Create.
    func compose(from paper: CustomPaper) {
        var draft = paper
        draft.id = "custom-\(UUID().uuidString.lowercased())"
        draft.seed = .random(in: .min ... .max)
        present(
            draft: draft,
            isNew: true,
            title: "New Paper"
        )
    }

    private func present(draft: CustomPaper, isNew: Bool, title: String) {
        window?.close()
        let editor = PaperMillView(
            draft: draft,
            isNew: isNew
        ) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingController(rootView: editor)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.minSize = NSSize(width: 400, height: 500)
        window.delegate = self

        // Position beside the actual MenuBarExtra content window. Generic
        // panels include the colour picker and the status-item host itself.
        if let menuWindow = NSApp.windows.first(where: {
            String(describing: type(of: $0)).contains("MenuBarExtra")
                && $0.isVisible
                && $0.frame.width > 100
        }) {
            let spacing: CGFloat = 12
            let screen = NSScreen.screens.first { $0.frame.intersects(menuWindow.frame) } ?? NSScreen.main
            let bounds = screen?.visibleFrame ?? menuWindow.frame
            let targetWidth = min(430, bounds.width)
            let targetHeight = min(bounds.height, min(720, max(580, menuWindow.frame.height)))
            let leftX = menuWindow.frame.minX - targetWidth - spacing
            let rightX = menuWindow.frame.maxX + spacing
            let targetX: CGFloat
            if leftX >= bounds.minX {
                targetX = leftX
            } else if rightX + targetWidth <= bounds.maxX {
                targetX = rightX
            } else {
                targetX = min(max(bounds.minX, leftX), bounds.maxX - targetWidth)
                menuWindow.orderOut(nil)
            }
            let targetY = min(
                max(bounds.minY, menuWindow.frame.maxY - targetHeight),
                bounds.maxY - targetHeight
            )
            window.setFrame(
                NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight),
                display: true
            )
        } else {
            window.center()
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        self.isOpen = true
    }

    /// Closing the editor by any route — Cancel, Save, Delete or the window's
    /// own close button — tears the preview down.
    func windowWillClose(_ notification: Notification) {
        AppState.shared.previewPaper = nil
        window = nil
        isOpen = false
    }
}

private struct PaperMillThumbnail: View, Equatable {
    let preset: TexturePreset
    let isAdjusting: Bool

    static func == (lhs: PaperMillThumbnail, rhs: PaperMillThumbnail) -> Bool {
        lhs.preset == rhs.preset && lhs.isAdjusting == rhs.isAdjusting
    }

    var body: some View {
        Image(nsImage: TextureRenderer.preview(
            for: preset,
            size: CGSize(width: 380, height: 130),
            backingScale: isAdjusting ? 1 : 2,
            cached: false
        ))
        .resizable()
        .aspectRatio(380.0 / 130.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
    }
}

private struct PaperMillView: View {
    @State var draft: CustomPaper
    let isNew: Bool
    let dismiss: () -> Void

    @ObservedObject private var state = AppState.shared
    @State private var isPreviewing = false
    /// Set between a control change and the debounce firing. The thumbnail
    /// renders at 1x while it is true so a weave/blotch drag never stalls on a
    /// full 2x spectral synthesis.
    @State private var isAdjusting = false
    @State private var pushTask: Task<Void, Never>?

    private var previewPreset: TexturePreset { TexturePreset(custom: draft) }
    private var comfort: PaperComfort {
        PaperComfort.evaluate(paper: draft, intensity: state.intensity)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                PaperMillThumbnail(preset: previewPreset, isAdjusting: isAdjusting)
                    .equatable()

                // 2. On-Screen Live Preview Control Row
                HStack(spacing: 10) {
                    Button(action: togglePreview) {
                        HStack(spacing: 6) {
                            Image(systemName: isPreviewing ? "eye.slash.fill" : "eye.fill")
                            Text(isPreviewing ? "Stop Preview" : "Preview on Screen")
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isPreviewing ? .green : .accentColor)
                    .keyboardShortcut("p", modifiers: .command)

                    Text(isPreviewing
                         ? "Live on screen — this window is under the overlay too."
                         : "Renders the draft on every display before you save it.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 3. Name Field
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)

                // 4. Comfort Recipes Row
                VStack(alignment: .leading, spacing: 5) {
                    Text("Comfort Starting Points")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(PaperComfort.recipes) { recipe in
                            Button(recipe.name) {
                                recipe.apply(to: &draft)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(recipe.detail)
                        }
                    }
                }

                // 5. Paper Properties & Sliders
                ColorPicker("Tint", selection: tintBinding, supportsOpacity: false)

                labeledSlider("Wash", value: $draft.wash, range: 0.10...0.60)
                labeledSlider("Weave", value: $draft.weave, range: 0...0.35)
                labeledSlider("Blotch", value: $draft.blotch, range: 0...0.40)

                // 6. Eye Comfort Evaluation Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Eye Comfort & Contrast")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(comfort.grade.rawValue)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(gradeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(gradeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            comfortMetric(label: "Brightness", value: "−\(Int((comfort.dimming * 100).rounded()))%")
                            comfortMetric(label: "Contrast", value: String(format: "%.1f:1", comfort.contrastRatio))
                            comfortMetric(label: "Blue Light", value: "−\(Int((comfort.blueReduction * 100).rounded()))%")
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 3) {
                            comfortMetric(label: "Tint Temp", value: "\(Int(comfort.temperature.rounded())) K (\(temperatureDescription))")
                            comfortMetric(label: "Pattern Load", value: "\(Int((comfort.patternLoad * 100).rounded()))%")
                            comfortMetric(label: "Veil Alpha", value: "\(Int((comfort.veil * 100).rounded()))%")
                        }
                    }

                    if comfort.needsContrastWarning {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text("This paper removes over 30% of bare-screen contrast — lower Wash or Intensity for crisper text.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // 7. Live Intensity Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Intensity")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(state.intensity * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $state.intensity,
                        in: 0.05...0.45,
                        onEditingChanged: { isAdjusting = $0 }
                    )
                    Text("Shared with the menu — the level this paper will actually be seen at.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // 8. Bottom Action Buttons
                HStack {
                    if !isNew {
                        Button("Delete", role: .destructive) {
                            stopPreview()
                            AppState.shared.customPapers.removeAll { $0.id == draft.id }
                            dismiss()
                        }
                    }
                    Spacer()
                    Button("Cancel") {
                        stopPreview()
                        dismiss()
                    }
                    Button(isNew ? "Create" : "Save") {
                        stopPreview()
                        var papers = AppState.shared.customPapers
                        if let index = papers.firstIndex(where: { $0.id == draft.id }) {
                            papers[index] = draft
                        } else {
                            papers.append(draft)
                        }
                        AppState.shared.customPapers = papers
                        AppState.shared.textureID = draft.id
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
        }
        .frame(minWidth: 400, maxWidth: 600, minHeight: 500, maxHeight: 800)
        .onChange(of: previewPreset) { _ in
            schedulePreviewPush()
        }
        .onDisappear {
            pushTask?.cancel()
        }
    }

    private var gradeColor: Color {
        switch comfort.grade {
        case .excellent, .good: return .green
        case .reduced: return .orange
        case .poor: return .red
        }
    }

    private var temperatureDescription: String {
        if comfort.temperature < 3500 {
            return "Warm"
        } else if comfort.temperature <= 5000 {
            return "Neutral"
        } else {
            return "Cool"
        }
    }

    private func comfortMetric(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func togglePreview() {
        isPreviewing.toggle()
        state.previewPaper = isPreviewing ? draft : nil
    }

    private func stopPreview() {
        pushTask?.cancel()
        isPreviewing = false
        state.previewPaper = nil
    }

    private func schedulePreviewPush() {
        isAdjusting = true
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isAdjusting = false
            if isPreviewing {
                state.previewPaper = draft
            }
        }
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: {
                Color(.sRGB, red: draft.tintRed, green: draft.tintGreen, blue: draft.tintBlue)
            },
            set: { color in
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
                draft.tintRed = ns.redComponent
                draft.tintGreen = ns.greenComponent
                draft.tintBlue = ns.blueComponent
            }
        )
    }

    private func labeledSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 48, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Export / import

enum PaperFiles {
    static func export(_ paper: CustomPaper) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(paper.name).decklepaper.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? encoder.encode(paper)).map { try $0.write(to: url) }
    }

    static func importPapers() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.message = "Choose .decklepaper.json files"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url),
                  var paper = try? JSONDecoder().decode(CustomPaper.self, from: data) else { continue }
            // Fresh id so an import can never silently overwrite a local paper.
            paper.id = "custom-\(UUID().uuidString.lowercased())"
            AppState.shared.customPapers.append(paper)
        }
    }
}
