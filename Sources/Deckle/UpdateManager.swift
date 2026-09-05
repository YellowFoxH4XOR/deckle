import AppKit
import Combine

/// Lightweight self-updater backed by GitHub Releases: checks
/// repos/YellowFoxH4XOR/deckle/releases/latest daily, compares versions, and
/// either surfaces an "Update" button in the menu or — when the user enables
/// automatic updates — downloads the DMG and swaps the app bundle in place.
/// When in-place replacement is impossible, the failure explains itself; the
/// browser is never hijacked without an explicit install click.
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
                // Flipping the toggle is not an install click; never browser.
                installLatest(userInitiated: false)
            }
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Internal, not private: deterministic tests stage it. Only `check()`
    /// writes it in production, and only from this pinned-URL block.
    var downloadURL: URL?
    /// Newest version seen in a release, kept so dismissing a failure banner
    /// restores the "update available" affordance instead of stranding it.
    var latestKnownVersion: String?
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
                downloadURL = nil
                latestKnownVersion = nil
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
            latestKnownVersion = latest
            status = .available(latest)
            if autoInstall {
                // An auto-install was never an install click — no browser.
                installLatest(userInitiated: false)
            }
        } catch {
            // Quiet failure for background checks; only surface when asked.
            if userInitiated { status = .failed("Couldn't reach GitHub") }
        }
    }

    /// Why in-place self-replacement cannot happen. Classification is a pure,
    /// nonisolated function of the bundle path plus one file-manager fact, so
    /// every branch is testable without touching disk.
    enum InstallBlocker: Equatable, CaseIterable {
        case translocated
        case notAnApp
        case locationNotWritable

        /// Every message names /Applications: a bounced "Update" click must
        /// tell the user exactly where the app has to live to self-update.
        var userMessage: String {
            switch self {
            case .translocated:
                return "macOS is running Deckle from its download location, so it can't replace itself. Drag Deckle.app to /Applications once — updates install in place after that."
            case .notAnApp:
                return "Deckle isn't running as an app bundle, so it can't update itself. Install Deckle.app into /Applications and relaunch."
            case .locationNotWritable:
                return "Deckle can't write where it lives (running from a mounted disk image?). Move Deckle.app to /Applications to update in place."
            }
        }
    }

    nonisolated static func selfReplaceBlocker(bundleURL: URL, installDirWritable: Bool) -> InstallBlocker? {
        // Translocation is checked first: those paths still end in ".app",
        // but the shown path is a randomized read-only mount whose real
        // install location is unknowable.
        if bundleURL.path.contains("/AppTranslocation/") { return .translocated }
        guard bundleURL.pathExtension == "app" else { return .notAnApp }
        guard installDirWritable else { return .locationNotWritable }
        return nil
    }

    /// - Parameter userInitiated: the user explicitly asked to install now,
    ///   which alone licenses handing off to the browser (only possible when
    ///   the release has no downloadable .dmg). Background checks and the
    ///   auto-install path must never touch the default app.
    func installLatest(userInitiated: Bool) {
        let target = Bundle.main.bundleURL
        installLatest(
            userInitiated: userInitiated,
            target: target,
            installDirWritable: FileManager.default.isWritableFile(
                atPath: target.deletingLastPathComponent().path
            )
        ) {
            NSWorkspace.shared.open($0)
        }
    }

    /// Seam-injected core so the browser-hijack guarantee and the classifier
    /// are testable without moving real bundles, probing real install dirs,
    /// or spawning real browsers.
    func installLatest(userInitiated: Bool, target: URL, installDirWritable: Bool, openReleasesPage: (URL) -> Void) {
        // Two swaps racing on one bundle path can't both be safe.
        guard status != .installing else { return }

        if let blocker = Self.selfReplaceBlocker(bundleURL: target, installDirWritable: installDirWritable) {
            // Stay put and explain: the recovery is moving the app, not
            // downloading it again. The banner's manual link covers that.
            status = .failed(blocker.userMessage)
            return
        }
        // Only ever download release assets of this repo over HTTPS, so a
        // missing .dmg means the pinned host has nothing safe to swap in.
        guard let dmg = downloadURL else {
            status = .failed("Couldn't find the update download on GitHub releases.")
            if userInitiated { openReleasesPage(releasesPage) }
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

    /// Manual escape hatch offered by the failure banner.
    func openReleases() {
        NSWorkspace.shared.open(releasesPage)
    }

    /// Clears a surfaced failure once the user acknowledges it, restoring the
    /// still-true "update available" state when there is one.
    func acknowledgeFailure() {
        guard case .failed = status else { return }
        status = latestKnownVersion.map(Status.available) ?? .idle
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
