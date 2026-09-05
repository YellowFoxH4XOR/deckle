import XCTest
@testable import Deckle

/// Pins the updater's decisions without mutating its private pinned-release
/// state, touching a real app bundle, or opening a browser.
@MainActor
final class UpdateManagerTests: XCTestCase {
    private let translocatedPath = "/private/var/folders/zz/zy/AppTranslocation/"
        + "D7C484A9-5915-4468-B6E9-11959001A111/d/Deckle.app"
    private let pinnedDownload =
        "https://github.com/YellowFoxH4XOR/deckle/releases/download/v1.7.3/Deckle-1.7.3.dmg"

    // MARK: - Bundle classification

    func testNormalInstallLocationCanSelfReplace() {
        XCTAssertNil(UpdateManager.selfReplaceBlocker(
            bundleURL: URL(fileURLWithPath: "/Applications/Deckle.app"),
            installDirWritable: true
        ))
    }

    func testTranslocationTakesPrecedenceOverEverythingElse() {
        for writable in [true, false] {
            XCTAssertEqual(UpdateManager.selfReplaceBlocker(
                bundleURL: URL(fileURLWithPath: translocatedPath),
                installDirWritable: writable
            ), .translocated)
        }
    }

    func testLooseBinaryReportsNotAnApp() {
        XCTAssertEqual(UpdateManager.selfReplaceBlocker(
            bundleURL: URL(fileURLWithPath: "/usr/local/bin/Deckle"),
            installDirWritable: true
        ), .notAnApp)
    }

    func testReadOnlyInstallDirectoryReportsNotWritable() {
        XCTAssertEqual(UpdateManager.selfReplaceBlocker(
            bundleURL: URL(fileURLWithPath: "/Volumes/Deckle/Deckle.app"),
            installDirWritable: false
        ), .locationNotWritable)
    }

    // MARK: - Install decisions

    func testBlockedInstallExplainsItselfAndNeverOpensBrowser() {
        let decision = UpdateManager.installDecision(
            currentStatus: .available("1.7.3"),
            bundleURL: URL(fileURLWithPath: translocatedPath),
            installDirWritable: true,
            hasDownload: true,
            userInitiated: true
        )

        XCTAssertEqual(decision.status, .failed(UpdateManager.InstallBlocker.translocated.userMessage))
        XCTAssertEqual(decision.action, .none)
    }

    func testMissingAssetOpensReleasesOnlyAfterExplicitInstallClick() {
        let background = UpdateManager.installDecision(
            currentStatus: .available("1.7.3"),
            bundleURL: URL(fileURLWithPath: "/Applications/Deckle.app"),
            installDirWritable: true,
            hasDownload: false,
            userInitiated: false
        )
        let explicit = UpdateManager.installDecision(
            currentStatus: .available("1.7.3"),
            bundleURL: URL(fileURLWithPath: "/Applications/Deckle.app"),
            installDirWritable: true,
            hasDownload: false,
            userInitiated: true
        )

        XCTAssertEqual(background.action, .none)
        XCTAssertEqual(explicit.action, .openReleases)
        XCTAssertEqual(background.status, explicit.status)
    }

    func testInstallingBlocksReentrancy() {
        let decision = UpdateManager.installDecision(
            currentStatus: .installing,
            bundleURL: URL(fileURLWithPath: translocatedPath),
            installDirWritable: false,
            hasDownload: false,
            userInitiated: true
        )

        XCTAssertEqual(decision, UpdateManager.InstallDecision(status: .installing, action: .none))
    }

    // MARK: - Release transition

    func testAutomaticUpdateTransitionIsNeverUserInitiated() throws {
        let transition = try UpdateManager.releaseTransition(
            from: releaseData(downloadURL: pinnedDownload),
            currentVersion: "1.7.2",
            userInitiated: true,
            autoInstallEnabled: true
        )

        XCTAssertEqual(transition.status, .available("1.7.3"))
        XCTAssertEqual(transition.version, "1.7.3")
        XCTAssertEqual(transition.downloadURL?.absoluteString, pinnedDownload)
        XCTAssertEqual(transition.installUserInitiated, false)
    }

    func testReleaseTransitionRejectsUnpinnedAssetOrigin() throws {
        let transition = try UpdateManager.releaseTransition(
            from: releaseData(downloadURL: "https://example.com/Deckle-1.7.3.dmg"),
            currentVersion: "1.7.2",
            userInitiated: false,
            autoInstallEnabled: false
        )

        XCTAssertEqual(transition.status, .available("1.7.3"))
        XCTAssertNil(transition.downloadURL)
        XCTAssertNil(transition.installUserInitiated)
    }

    func testCurrentReleaseClearsAvailableUpdateState() throws {
        let transition = try UpdateManager.releaseTransition(
            from: releaseData(downloadURL: pinnedDownload),
            currentVersion: "1.7.3",
            userInitiated: true,
            autoInstallEnabled: true
        )

        XCTAssertEqual(transition.status, .upToDate)
        XCTAssertNil(transition.version)
        XCTAssertNil(transition.downloadURL)
        XCTAssertNil(transition.installUserInitiated)
    }

    // MARK: - Failure dismissal

    func testFailureDismissalRestoresAndDismissesKnownVersionTogether() {
        let dismissal = UpdateManager.failureDismissal(
            status: .failed("Move Deckle"),
            latestKnownVersion: "1.7.3"
        )

        XCTAssertEqual(dismissal.restoredStatus, .available("1.7.3"))
        XCTAssertEqual(dismissal.dismissedVersion, "1.7.3")
    }

    func testFailureDismissalFallsToIdleWithoutKnownVersion() {
        let dismissal = UpdateManager.failureDismissal(
            status: .failed("Couldn't reach GitHub"),
            latestKnownVersion: nil
        )

        XCTAssertEqual(dismissal.restoredStatus, .idle)
        XCTAssertNil(dismissal.dismissedVersion)
    }

    private func releaseData(downloadURL: String) -> Data {
        Data("""
        {
          "tag_name": "v1.7.3",
          "assets": [
            {
              "name": "Deckle-1.7.3.dmg",
              "browser_download_url": "\(downloadURL)"
            }
          ]
        }
        """.utf8)
    }
}
