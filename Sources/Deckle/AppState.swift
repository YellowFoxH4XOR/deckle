import AppKit
import Combine

/// Central observable state. The menu UI writes to it; the overlay controller
/// observes it and updates the on-screen windows.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Overall overlay opacity (drives the overlay windows' alphaValue).
    @Published var intensity: Double {
        didSet { defaults.set(intensity, forKey: Keys.intensity) }
    }

    @Published var textureID: String {
        didSet { defaults.set(textureID, forKey: Keys.texture) }
    }

    /// While set to a future date, the overlay hides even if isEnabled.
    @Published var snoozeUntil: Date? {
        didSet { scheduleSnoozeExpiry() }
    }

    /// Display IDs (as strings) the overlay should skip.
    @Published var excludedDisplays: Set<String> {
        didSet { defaults.set(Array(excludedDisplays), forKey: Keys.excluded) }
    }

    var texture: TexturePreset { TexturePreset.preset(id: textureID) }

    var isSnoozed: Bool {
        guard let until = snoozeUntil else { return false }
        return until > Date()
    }

    var shouldShowOverlay: Bool { isEnabled && !isSnoozed }

    func snooze(minutes: Int) {
        snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func cancelSnooze() {
        snoozeUntil = nil
    }

    // MARK: - Private

    private enum Keys {
        static let enabled = "isEnabled"
        static let intensity = "intensity"
        static let texture = "textureID"
        static let excluded = "excludedDisplays"
    }

    private let defaults = UserDefaults.standard
    private var snoozeTimer: Timer?

    private init() {
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        intensity = defaults.object(forKey: Keys.intensity) as? Double ?? 0.22
        textureID = defaults.string(forKey: Keys.texture) ?? TexturePreset.all[0].id
        excludedDisplays = Set(defaults.stringArray(forKey: Keys.excluded) ?? [])
    }

    private func scheduleSnoozeExpiry() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        guard let until = snoozeUntil, until > Date() else { return }
        snoozeTimer = Timer.scheduledTimer(
            withTimeInterval: until.timeIntervalSinceNow,
            repeats: false
        ) { [weak self] _ in
            self?.snoozeUntil = nil
        }
    }
}
