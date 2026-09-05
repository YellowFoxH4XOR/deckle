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

    enum InstallAction: Equatable {
        case none
        case openReleases
        case install
    }

    struct InstallDecision: Equatable {
        let status: Status
        let action: InstallAction
    }

    struct ReleaseTransition: Equatable {
        let status: Status
        let version: String?
        let downloadURL: URL?
        let installUserInitiated: Bool?
    }

    struct FailureDismissal: Equatable {
        let restoredStatus: Status
        let dismissedVersion: String?
    }

    private struct AvailableUpdate {
        let version: String
        let downloadURL: URL?
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

    /// Version and pinned asset URL move together. Only the GitHub response
    /// transition below can create this private install state.
    private var availableUpdate: AvailableUpdate?

    var latestKnownVersion: String? {
        availableUpdate?.version
    }
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
            let transition = try Self.releaseTransition(
                from: data,
                currentVersion: currentVersion,
                userInitiated: userInitiated,
                autoInstallEnabled: autoInstall
            )

            availableUpdate = transition.version.map {
                AvailableUpdate(version: $0, downloadURL: transition.downloadURL)
            }
            status = transition.status
            if let installUserInitiated = transition.installUserInitiated {
                installLatest(userInitiated: installUserInitiated)
            }
        } catch {
            // Quiet failure for background checks; only surface when asked.
            if userInitiated { status = .failed("Couldn't reach GitHub") }
        }
    }

    /// Why in-place self-replacement cannot happen. Classification is a pure,
    /// nonisolated function of the bundle path plus one file-manager fact.
    enum InstallBlocker: Equatable {
        case translocated
        case notAnApp
        case locationNotWritable

        nonisolated var userMessage: String {
            switch self {
            case .translocated:
                return "macOS is running Deckle from a protected download location. Move it to /Applications or ~/Applications, then try again."
            case .notAnApp:
                return "Deckle isn't running as an app bundle. Install Deckle.app in /Applications or ~/Applications, then reopen it."
            case .locationNotWritable:
                return "Deckle can't write to this folder. Move it to ~/Applications, or install the update manually."
            }
        }
    }

    nonisolated static func releaseTransition(
        from data: Data,
        currentVersion: String,
        userInitiated: Bool,
        autoInstallEnabled: Bool
    ) throws -> ReleaseTransition {
        let release = try JSONDecoder().decode(Release.self, from: data)
        let latest = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard isNewer(latest, than: currentVersion) else {
            return ReleaseTransition(
                status: userInitiated ? .upToDate : .idle,
                version: nil,
                downloadURL: nil,
                installUserInitiated: nil
            )
        }

        // Only release assets from this repository can enter install state.
        let downloadURL = release.assets.first { $0.name.hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browserDownloadUrl) }
            .flatMap { url in
                url.scheme == "https"
                    && url.host == "github.com"
                    && url.path.hasPrefix("/YellowFoxH4XOR/deckle/releases/download/")
                    ? url : nil
            }

        return ReleaseTransition(
            status: .available(latest),
            version: latest,
            downloadURL: downloadURL,
            installUserInitiated: autoInstallEnabled ? false : nil
        )
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

    nonisolated static func installDecision(
        currentStatus: Status,
        bundleURL: URL,
        installDirWritable: Bool,
        hasDownload: Bool,
        userInitiated: Bool
    ) -> InstallDecision {
        guard currentStatus != .installing else {
            return InstallDecision(status: .installing, action: .none)
        }
        if let blocker = selfReplaceBlocker(
            bundleURL: bundleURL,
            installDirWritable: installDirWritable
        ) {
            return InstallDecision(status: .failed(blocker.userMessage), action: .none)
        }
        guard hasDownload else {
            return InstallDecision(
                status: .failed("Couldn't find the update download on GitHub releases."),
                action: userInitiated ? .openReleases : .none
            )
        }
        return InstallDecision(status: .installing, action: .install)
    }

    /// Only an explicit install click may hand off to the browser. Background
    /// checks and automatic installs always surface a message in the menu.
    func installLatest(userInitiated: Bool) {
        let target = Bundle.main.bundleURL
        let update = availableUpdate
        let decision = Self.installDecision(
            currentStatus: status,
            bundleURL: target,
            installDirWritable: FileManager.default.isWritableFile(
                atPath: target.deletingLastPathComponent().path
            ),
            hasDownload: update?.downloadURL != nil,
            userInitiated: userInitiated
        )
        status = decision.status

        switch decision.action {
        case .none:
            return
        case .openReleases:
            NSWorkspace.shared.open(releasesPage)
        case .install:
            guard let dmg = update?.downloadURL else { return }
            Task {
                do {
                    try await selfReplace(target: target, dmg: dmg)
                    relaunch(target)
                } catch {
                    status = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Manual escape hatch offered by the failure banner.
    func openReleases() {
        NSWorkspace.shared.open(releasesPage)
    }

    nonisolated static func failureDismissal(
        status: Status,
        latestKnownVersion: String?
    ) -> FailureDismissal {
        guard case .failed = status else {
            return FailureDismissal(restoredStatus: status, dismissedVersion: nil)
        }
        return FailureDismissal(
            restoredStatus: latestKnownVersion.map(Status.available) ?? .idle,
            dismissedVersion: latestKnownVersion
        )
    }

    /// Clears a surfaced failure while preserving a known available update.
    func acknowledgeFailure() {
        let dismissal = Self.failureDismissal(
            status: status,
            latestKnownVersion: latestKnownVersion
        )
        status = dismissal.restoredStatus
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

    private nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
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
