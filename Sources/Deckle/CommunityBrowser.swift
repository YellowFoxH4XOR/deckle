import SwiftUI
import AppKit

/// Browses community-contributed papers from the deckle-papers repo:
/// a static index.json served by GitHub — no backend, contributions are PRs.
@MainActor
final class CommunityBrowser: ObservableObject {
    static let shared = CommunityBrowser()

    struct Entry: Codable, Identifiable {
        let file: String
        let name: String
        let author: String
        let description: String
        var id: String { file }
    }

    enum Status: Equatable {
        case idle, loading, loaded, failed(String)
    }

    @Published var entries: [Entry] = []
    @Published var status: Status = .idle
    @Published var installing: Set<String> = []
    @Published var installFailures: [String: String] = [:]

    private var window: NSWindow?
    private static let base = "https://raw.githubusercontent.com/YellowFoxH4XOR/deckle-papers/main"

    func open() {
        MenuDismiss.dismiss()
        if window == nil {
            let hosting = NSHostingController(rootView: CommunityView(browser: self))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Community Papers"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.center()
            self.window = window
        }
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if status == .idle { Task { await load() } }
    }

    func load() async {
        status = .loading
        do {
            let url = URL(string: "\(Self.base)/index.json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            entries = try JSONDecoder().decode([Entry].self, from: data)
            status = .loaded
        } catch {
            status = .failed("Couldn't load the community index")
        }
    }

    /// Strips every `..` sequence so only files listed by the index are fetched, never arbitrary paths.
    static func sanitizedPath(_ file: String) -> String {
        var path = file
        while path.contains("..") {
            path = path.replacingOccurrences(of: "..", with: "")
        }
        return path
    }

    /// Decodes a community paper and assigns it a fresh id so installs never overwrite local papers.
    static func importedPaper(from data: Data) throws -> CustomPaper {
        var paper = try JSONDecoder().decode(CustomPaper.self, from: data)
        paper.id = "custom-\(UUID().uuidString.lowercased())"
        return paper
    }

    func install(_ entry: Entry) async {
        guard !installing.contains(entry.id) else { return }
        installing.insert(entry.id)
        installFailures[entry.id] = nil
        defer { installing.remove(entry.id) }
        do {
            let file = Self.sanitizedPath(entry.file)
            guard let url = URL(string: "\(Self.base)/papers/\(file)") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }
            let paper = try Self.importedPaper(from: data)
            AppState.shared.customPapers.append(paper)
            AppState.shared.textureID = paper.id
        } catch {
            NSLog("[Deckle community] install failed: \(entry.file): \(error.localizedDescription)")
            installFailures[entry.id] = "Couldn't install this paper"
        }
    }
}

private struct CommunityView: View {
    @ObservedObject var browser: CommunityBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch browser.status {
            case .idle, .loading:
                ProgressView("Loading community papers…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry") { Task { await browser.load() } }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .loaded:
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(browser.entries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name).font(.body)
                                    Text("\(entry.description) — \(entry.author)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let failure = browser.installFailures[entry.id] {
                                        Text(failure)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                                Spacer()
                                let isInstalling = browser.installing.contains(entry.id)
                                let label = isInstalling ? "…"
                                    : browser.installFailures[entry.id] == nil ? "Install" : "Retry"
                                Button(label) {
                                    Task { await browser.install(entry) }
                                }
                                .disabled(isInstalling)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 320)
            }
            Divider()
            HStack {
                Text("Papers are community PRs — add yours!")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Link("deckle-papers on GitHub ↗",
                     destination: URL(string: "https://github.com/YellowFoxH4XOR/deckle-papers")!)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
