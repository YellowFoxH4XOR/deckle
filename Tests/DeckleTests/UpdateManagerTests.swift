import XCTest
@testable import Deckle

/// The defect this suite pins: a bounced "Update" used to be silent (browser
/// tab, no explanation) and any auto-install path could hijack the browser on
/// a background check. Both are asserted through the seam-injected
/// `installLatest(userInitiated:target:installDirWritable:openReleasesPage:)`,
/// which never launches a real `selfReplace` Task: every test either blocks
/// in the classifier or finds no download URL.
@MainActor
final class UpdateManagerTests: XCTestCase {
    private var updater: UpdateManager { UpdateManager.shared }
    private let translocatedPath = "/private/var/folders/zz/zy/AppTranslocation/"
        + "D7C484A9-5915-4468-B6E9-11959001A111/d/Deckle.app"

    override func setUp() {
        super.setUp()
        reset()
    }

    override func tearDown() {
        reset()
        super.tearDown()
    }

    /// The manager is a process-wide singleton; leave no state behind.
    private func reset() {
        updater.status = .idle
        updater.downloadURL = nil
        updater.latestKnownVersion = nil
    }

    // MARK: - Classifier

    func testNormalInstallLocationCanSelfReplace() {
        XCTAssertNil(UpdateManager.selfReplaceBlocker(
            bundleURL: URL(fileURLWithPath: "/Applications/Deckle.app"),
            installDirWritable: true
        ))
    }

    func testTranslocationTakesPrecedenceOverEverythingElse() {
        // Same path reports writable or not — the shown path is a randomized
        // read-only mount either way, so classification must not depend on it.
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

    func testEveryBlockerMessageNamesTheRecoveryLocation() {
        // Contract, not prose styling: whatever failed, the user is told
        // where the app has to live for in-place updates to work.
        for blocker in UpdateManager.InstallBlocker.allCases {
            XCTAssertTrue(
                blocker.userMessage.contains("Applications"),
                "\(blocker) message omits the recovery location"
            )
        }
    }

    // MARK: - Install behavior (the actual regression)

    func testBlockedInstallExplainsItselfAndNeverOpensBrowser() {
        updater.status = .available("9.9.9")
        updater.downloadURL = URL(
            string: "https://github.com/YellowFoxH4XOR/deckle/releases/download/v9.9.9/Deckle-9.9.9.dmg"
        )!
        var opened: [URL] = []

        // Even a user-initiated click must not launch a browser when the
        // bundle is translocated; the message is the action.
        updater.installLatest(
            userInitiated: true,
            target: URL(fileURLWithPath: translocatedPath),
            installDirWritable: true
        ) { opened.append($0) }

        XCTAssertEqual(updater.status, .failed(UpdateManager.InstallBlocker.translocated.userMessage))
        XCTAssertTrue(opened.isEmpty)
    }

    func testMissingAssetHandsOffToReleasesOnlyOnExplicitClick() {
        var opened: [URL] = []
        updater.installLatest(
            userInitiated: false,
            target: URL(fileURLWithPath: "/Applications/Deckle.app"),
            installDirWritable: true
        ) { opened.append($0) }
        XCTAssertEqual(opened.count, 0, "background install must never open the browser")
        XCTAssertEqual(updater.status, .failed("Couldn't find the update download on GitHub releases."))

        updater.installLatest(
            userInitiated: true,
            target: URL(fileURLWithPath: "/Applications/Deckle.app"),
            installDirWritable: true
        ) { opened.append($0) }
        XCTAssertEqual(opened.count, 1, "explicit click may hand off when there is nothing to swap")
    }

    func testInstallingBlocksReentrancy() {
        updater.status = .installing
        var opened: [URL] = []
        updater.installLatest(
            userInitiated: true,
            target: URL(fileURLWithPath: translocatedPath),
            installDirWritable: true
        ) { opened.append($0) }
        // The guard returns before classification; status untouched.
        XCTAssertEqual(updater.status, .installing)
        XCTAssertTrue(opened.isEmpty)
    }

    // MARK: - Acknowledge

    func testAcknowledgeRestoresKnownAvailableUpdate() {
        updater.latestKnownVersion = "1.2.3"
        updater.status = .failed("whatever")
        updater.acknowledgeFailure()
        XCTAssertEqual(updater.status, .available("1.2.3"))
    }

    func testAcknowledgeFallsToIdleWithoutKnownUpdateAndIgnoresOtherStates() {
        updater.status = .failed("whatever")
        updater.acknowledgeFailure()
        XCTAssertEqual(updater.status, .idle)

        updater.status = .installing
        updater.acknowledgeFailure()
        XCTAssertEqual(updater.status, .installing)
    }
}
