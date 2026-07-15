import AppKit
import Combine

/// Lightweight self-updater backed by GitHub Releases: checks
/// repos/YellowFoxH4XOR/deckle/releases/latest daily, compares versions, and
/// either surfaces an "Update" button in the menu or — when the user enables
/// automatic updates — downloads the DMG and swaps the app bundle in place.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case installing
        case failed(String)
    }

    @Published var status: Status = .idle

    /// When on, a found update installs without asking.
    @Published var autoInstall: Bool {
        didSet {
            UserDefaults.standard.set(autoInstall, forKey: "autoInstallUpdates")
            if autoInstall, case .available = status {
                installLatest()
            }
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var downloadURL: URL?
    private var checkTimer: Timer?
    private let releasesPage = URL(string: "https://github.com/YellowFoxH4XOR/deckle/releases/latest")!
    private let apiURL = URL(string: "https://api.github.com/repos/YellowFoxH4XOR/deckle/releases/latest")!

    private init() {
        autoInstall = UserDefaults.standard.bool(forKey: "autoInstallUpdates")
    }

    func start() {
        // First check shortly after launch, then daily.
        Task {
            try? await Task.sleep(for: .seconds(5))
            await check()
        }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in await UpdateManager.shared.check() }
        }
    }

    func check(userInitiated: Bool = false) async {
        if userInitiated { status = .checking }
        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(Release.self, from: data)

            let latest = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            guard isNewer(latest, than: currentVersion) else {
                status = userInitiated ? .upToDate : .idle
                return
            }
            // Only ever download release assets of this repo over HTTPS —
            // never a URL the API response could have been tampered into.
            downloadURL = release.assets.first { $0.name.hasSuffix(".dmg") }
                .flatMap { URL(string: $0.browserDownloadUrl) }
                .flatMap { url in
                    url.scheme == "https"
                        && url.host == "github.com"
                        && url.path.hasPrefix("/YellowFoxH4XOR/deckle/releases/download/")
                        ? url : nil
                }
            status = .available(latest)
            if autoInstall {
                installLatest()
            }
        } catch {
            // Quiet failure for background checks; only surface when asked.
            if userInitiated { status = .failed("Couldn't reach GitHub") }
        }
    }

    func installLatest() {
        // Self-replace only makes sense for a bundle installed as
        // <something>/Deckle.app; otherwise send the user to the release.
        let target = Bundle.main.bundleURL
        guard let dmg = downloadURL, target.pathExtension == "app" else {
            NSWorkspace.shared.open(releasesPage)
            return
        }
        status = .installing
        Task {
            do {
                try await selfReplace(target: target, dmg: dmg)
                relaunch(target)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Install mechanics

    private func selfReplace(target: URL, dmg: URL) async throws {
        let (download, _) = try await URLSession.shared.download(from: dmg)
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("deckle-update-\(UUID().uuidString)")

        try run("/usr/bin/hdiutil", "attach", download.path,
                "-nobrowse", "-quiet", "-mountpoint", mount.path)
        defer { try? run("/usr/bin/hdiutil", "detach", mount.path, "-quiet") }

        let newApp = mount.appendingPathComponent("Deckle.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            throw UpdateError.badArchive
        }

        // Integrity gate before the swap: the code signature seal must
        // verify and the payload must actually be Deckle. Releases are
        // ad-hoc signed, so this proves the bundle is intact, not who built
        // it — origin trust comes from the pinned HTTPS release URL above.
        // (If Deckle adopts Developer ID signing, tighten this with
        // `-R="anchor apple generic and certificate leaf[subject.OU] = <team>"`.)
        try run("/usr/bin/codesign", "--verify", "--deep", "--strict", newApp.path)
        let newInfo = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        guard newInfo?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError.badArchive
        }

        // Stage on the destination volume, then swap — the running binary's
        // mapped pages stay valid even after its bundle is replaced.
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent("Deckle.app.update")
        try? FileManager.default.removeItem(at: staging)
        try run("/usr/bin/ditto", newApp.path, staging.path)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: staging, to: target)
    }

    private func relaunch(_ target: URL) {
        // Detached shell so the reopen survives our own termination.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", target.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func run(_ launchPath: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.toolFailed(launchPath)
        }
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private enum UpdateError: LocalizedError {
        case badArchive
        case toolFailed(String)

        var errorDescription: String? {
            switch self {
            case .badArchive: return "Update download looked wrong; not installing"
            case .toolFailed(let tool): return "\(tool) failed"
            }
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }
}
