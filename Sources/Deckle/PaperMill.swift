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

    var isDark: Bool {
        0.299 * tintRed + 0.587 * tintGreen + 0.114 * tintBlue < 0.5
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
            isDark: dark
        )
    }
}

/// The Paper Mill: a small standalone editor window for creating and editing
/// custom papers, with a live preview rendered by the real engine.
@MainActor
final class PaperMill {
    static let shared = PaperMill()
    private var window: NSWindow?

    func open(editing paper: CustomPaper? = nil) {
        window?.close()
        let editor = PaperMillView(
            draft: paper ?? CustomPaper(),
            isNew: paper == nil
        ) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
        let hosting = NSHostingController(rootView: editor)
        let window = NSWindow(contentViewController: hosting)
        window.title = paper == nil ? "New Paper" : "Edit Paper"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct PaperMillView: View {
    @State var draft: CustomPaper
    let isNew: Bool
    let dismiss: () -> Void

    private var previewPreset: TexturePreset { TexturePreset(custom: draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(nsImage: TextureRenderer.preview(
                for: previewPreset,
                size: CGSize(width: 340, height: 120),
                cached: false
            ))
            .resizable()
            .aspectRatio(340.0 / 120.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))

            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            ColorPicker("Tint", selection: tintBinding, supportsOpacity: false)

            labeledSlider("Wash", value: $draft.wash, range: 0.10...0.60)
            labeledSlider("Weave", value: $draft.weave, range: 0...0.35)
            labeledSlider("Blotch", value: $draft.blotch, range: 0...0.40)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        AppState.shared.customPapers.removeAll { $0.id == draft.id }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Create" : "Save") {
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
        .frame(width: 380)
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
