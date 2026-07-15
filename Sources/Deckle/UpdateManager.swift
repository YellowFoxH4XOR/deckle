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
    /// System-scheduled daily check: unlike a Timer, the OS coalesces the
    /// wakeup with other activity and prefers energy-cheap moments.
    private let checkActivity = NSBackgroundActivityScheduler(
        identifier: "app.deckle.Deckle.update-check"
    )
    private let releasesPage = URL(string: "https://github.com/YellowFoxH4XOR/deckle/releases/latest")!
    private let apiURL = URL(string: "https://api.github.com/repos/YellowFoxH4XOR/deckle/releases/latest")!

    private init() {
        autoInstall = UserDefaults.standard.bool(forKey: "autoInstallUpdates")
    }

    func start() {
        // First check shortly after launch, then roughly daily — the wide
        // tolerance lets macOS batch our wakeup with everything else's.
        Task {
            try? await Task.sleep(for: .seconds(5))
            await check()
        }
        checkActivity.repeats = true
        checkActivity.interval = 24 * 60 * 60
        checkActivity.tolerance = 4 * 60 * 60
        checkActivity.qualityOfService = .utility
        checkActivity.schedule { completion in
            Task { @MainActor in
                await UpdateManager.shared.check()
                completion(.finished)
            }
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
        let target = Bundle.main.bundleURL

        // In-place replacement only works when Deckle is a normal .app whose
        // enclosing folder we can write to. It can't when the app is running
        // "translocated" (Gatekeeper's read-only randomized path, used the
        // first time an unsigned app is opened from a DMG or Downloads) — the
        // real install location is then unknown, so hand off to the browser.
        let installDir = target.deletingLastPathComponent()
        let canSelfReplace = target.pathExtension == "app"
            && !target.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: installDir.path)

        guard let dmg = downloadURL, canSelfReplace else {
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

        // Stage a full copy on the destination volume, then swap it in with a
        // single atomic replace. ditto to a uniquely-named sibling avoids
        // colliding with any leftover from an interrupted attempt; the
        // running binary's mapped pages stay valid after its bundle is
        // replaced (the old inode lives until this process exits).
        let installDir = target.deletingLastPathComponent()
        let staging = installDir.appendingPathComponent("Deckle.app.update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try run("/usr/bin/ditto", newApp.path, staging.path)

        // The DMG-mounted copy carries no quarantine, but clear it defensively
        // so the swapped-in bundle never triggers a Gatekeeper prompt.
        try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", staging.path)

        // replaceItemAt is atomic on a single volume: no window where the app
        // is half-removed, and it fails cleanly (leaving the original intact)
        // instead of the previous remove-then-move, which could delete the
        // app and then fail to move the replacement in.
        _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
    }

    private func relaunch(_ target: URL) {
        // Detached shell so the reopen survives our own termination.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", target.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            NSLog("[Deckle updater] \(launchPath) exit \(process.terminationStatus): \(text)")
            throw UpdateError.toolFailed(
                "\((launchPath as NSString).lastPathComponent): \(text.isEmpty ? "exit \(process.terminationStatus)" : text)"
            )
        }
        return text
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
            case .toolFailed(let detail): return "Update failed — \(detail)"
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
