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

    /// When on, overlay windows opt out of screen capture — screenshots and
    /// recordings show clean content while the texture stays visible to you.
    @Published var hideFromCapture: Bool {
        didSet { defaults.set(hideFromCapture, forKey: Keys.hideFromCapture) }
    }

    /// Grain size multiplier (0.5 fine … 4 grainy), applied to every texture.
    @Published var grainScale: Double {
        didSet { defaults.set(grainScale, forKey: Keys.grainScale) }
    }

    /// Grain visibility multiplier (0.25 … 2), applied to every texture.
    @Published var grainStrength: Double {
        didSet { defaults.set(grainStrength, forKey: Keys.grainStrength) }
    }

    // MARK: Favorites & Desk Lamp

    /// Pinned favorite texture IDs for quick-access switching bar.
    @Published var favoriteTextureIDs: [String] {
        didSet { defaults.set(favoriteTextureIDs, forKey: Keys.favoriteTextureIDs) }
    }

    /// Whether Desk Lamp mode (warm ambient light pool over texture) is enabled.
    @Published var enableDeskLamp: Bool {
        didSet { defaults.set(enableDeskLamp, forKey: Keys.deskLamp) }
    }

    /// Color temperature/warmth of Desk Lamp (0.0 = cool/neutral, 1.0 = deep amber).
    @Published var deskLampWarmth: Double {
        didSet { defaults.set(deskLampWarmth, forKey: Keys.deskLampWarmth) }
    }

    /// Brightness/intensity of Desk Lamp pool (0.05 ... 0.50).
    @Published var deskLampBrightness: Double {
        didSet { defaults.set(deskLampBrightness, forKey: Keys.deskLampBrightness) }
    }

    /// Spread/radius of Desk Lamp light pool (0.3 ... 1.2).
    @Published var deskLampSpread: Double {
        didSet { defaults.set(deskLampSpread, forKey: Keys.deskLampSpread) }
    }

    enum LampPosition: String, CaseIterable, Identifiable {
        case topRight = "Top Right"
        case topLeft = "Top Left"
        case topCenter = "Top Center"
        case center = "Center"

        var id: String { rawValue }

        var point: CGPoint {
            switch self {
            case .topRight: return CGPoint(x: 0.85, y: 0.15)
            case .topLeft: return CGPoint(x: 0.15, y: 0.15)
            case .topCenter: return CGPoint(x: 0.50, y: 0.10)
            case .center: return CGPoint(x: 0.50, y: 0.50)
            }
        }
    }

    @Published var deskLampPosition: LampPosition {
        didSet { defaults.set(deskLampPosition.rawValue, forKey: Keys.deskLampPosition) }
    }

    func isFavorite(_ id: String) -> Bool {
        favoriteTextureIDs.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if isFavorite(id) {
            favoriteTextureIDs.removeAll { $0 == id }
        } else if favoriteTextureIDs.count < 6 {
            favoriteTextureIDs.append(id)
        }
    }

    var grainAdjustments: TextureRenderer.GrainAdjustments {
        .init(scale: grainScale, strength: grainStrength)
    }

    // MARK: App rules

    enum AppRuleMode: String, CaseIterable {
        case everywhere, except, only
    }

    struct RuleApp: Codable, Equatable, Identifiable {
        var bundleID: String
        var name: String
        var id: String { bundleID }
    }

    /// Whether the overlay shows everywhere, everywhere except listed apps,
    /// or only while a listed app is frontmost.
    @Published var appRuleMode: AppRuleMode {
        didSet { defaults.set(appRuleMode.rawValue, forKey: Keys.appRuleMode) }
    }

    @Published var ruleApps: [RuleApp] {
        didSet {
            if let data = try? JSONEncoder().encode(ruleApps) {
                defaults.set(data, forKey: Keys.ruleApps)
            }
        }
    }

    /// Visibility verdict for the given frontmost app. Deckle itself is
    /// always allowed so the overlay stays visible while using our own UI.
    func appRuleAllows(frontmost bundleID: String?) -> Bool {
        guard appRuleMode != .everywhere else { return true }
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return true }
        let listed = ruleApps.contains { $0.bundleID == bundleID }
        switch appRuleMode {
        case .everywhere: return true
        case .except: return !listed
        case .only: return listed
        }
    }

    /// User-created papers, editable in the Paper Mill.
    @Published var customPapers: [CustomPaper] {
        didSet {
            if let data = try? JSONEncoder().encode(customPapers) {
                defaults.set(data, forKey: Keys.customPapers)
            }
            // If the active paper was deleted, fall back to the default.
            if !customPapers.contains(where: { $0.id == textureID }),
               textureID.hasPrefix("custom-"),
               TexturePreset.all.first(where: { $0.id == textureID }) == nil {
                textureID = TexturePreset.all[0].id
            }
        }
    }

    var texture: TexturePreset {
        if let custom = customPapers.first(where: { $0.id == textureID }) {
            return TexturePreset(custom: custom)
        }
        return TexturePreset.preset(id: textureID)
    }

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
        static let hideFromCapture = "hideFromCapture"
        static let grainScale = "grainScale"
        static let grainStrength = "grainStrength"
        static let appRuleMode = "appRuleMode"
        static let ruleApps = "ruleApps"
        static let customPapers = "customPapers"
        static let favoriteTextureIDs = "favoriteTextureIDs"
        static let deskLamp = "enableDeskLamp"
        static let deskLampWarmth = "deskLampWarmth"
        static let deskLampBrightness = "deskLampBrightness"
        static let deskLampSpread = "deskLampSpread"
        static let deskLampPosition = "deskLampPosition"
    }

    private let defaults = UserDefaults.standard
    private var snoozeTimer: Timer?

    private init() {
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        intensity = defaults.object(forKey: Keys.intensity) as? Double ?? 0.22
        textureID = defaults.string(forKey: Keys.texture) ?? TexturePreset.all[0].id
        excludedDisplays = Set(defaults.stringArray(forKey: Keys.excluded) ?? [])
        hideFromCapture = defaults.bool(forKey: Keys.hideFromCapture)
        grainScale = defaults.object(forKey: Keys.grainScale) as? Double ?? 1.0
        grainStrength = defaults.object(forKey: Keys.grainStrength) as? Double ?? 1.0
        appRuleMode = AppRuleMode(rawValue: defaults.string(forKey: Keys.appRuleMode) ?? "") ?? .everywhere
        ruleApps = defaults.data(forKey: Keys.ruleApps)
            .flatMap { try? JSONDecoder().decode([RuleApp].self, from: $0) } ?? []
        customPapers = defaults.data(forKey: Keys.customPapers)
            .flatMap { try? JSONDecoder().decode([CustomPaper].self, from: $0) } ?? []
        favoriteTextureIDs = defaults.stringArray(forKey: Keys.favoriteTextureIDs)
            ?? ["classic-matte", "sunbaked-parchment", "whisper-weave", "carbon-ledger"]
        enableDeskLamp = defaults.bool(forKey: Keys.deskLamp)
        deskLampWarmth = defaults.object(forKey: Keys.deskLampWarmth) as? Double ?? 0.6
        deskLampBrightness = defaults.object(forKey: Keys.deskLampBrightness) as? Double ?? 0.25
        deskLampSpread = defaults.object(forKey: Keys.deskLampSpread) as? Double ?? 0.75
        deskLampPosition = LampPosition(rawValue: defaults.string(forKey: Keys.deskLampPosition) ?? "") ?? .topRight
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
        // A snooze ending seconds late is invisible; a coalesced CPU wakeup
        // is real battery savings.
        snoozeTimer?.tolerance = min(60, until.timeIntervalSinceNow * 0.1)
    }
}
