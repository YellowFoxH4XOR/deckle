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

    /// Matte finish strength: neutralizes bright highlights without adding visible grain.
    @Published var matteStrength: Double {
        didSet { defaults.set(matteStrength, forKey: Keys.matteStrength) }
    }

    var grainAdjustments: TextureRenderer.GrainAdjustments {
        .init(scale: grainScale, strength: grainStrength, matte: matteStrength)
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

    /// Draft paper the Paper Mill is previewing live on the real overlay
    /// windows. Deliberately not persisted and not written to `defaults` —
    /// it only ever lives as long as the editor window.
    @Published var previewPaper: CustomPaper?

    /// Comparison never changes saved settings or a running snooze.
    @Published var isComparingOriginal = false

    @Published var deskSetups: [DeskSetup] {
        didSet {
            if let data = try? JSONEncoder().encode(deskSetups) {
                defaults.set(data, forKey: Keys.deskSetups)
            }
        }
    }

    func paperExists(id: String) -> Bool {
        TexturePreset.all.contains { $0.id == id } || customPapers.contains { $0.id == id }
    }

    func matches(_ setup: DeskSetup) -> Bool {
        textureID == setup.textureID && abs(intensity - setup.intensity) < 0.00001
            && grainScale == setup.grainScale && abs(grainStrength - setup.grainStrength) < 0.00001
            && abs(matteStrength - setup.matteStrength) < 0.00001
    }

    @discardableResult
    func apply(_ setup: DeskSetup) -> Bool {
        guard setup.hasValidSettings, paperExists(id: setup.textureID), previewPaper == nil else { return false }
        isComparingOriginal = false
        textureID = setup.textureID
        intensity = setup.intensity
        grainScale = setup.grainScale
        grainStrength = setup.grainStrength
        matteStrength = setup.matteStrength
        cancelSnooze()
        isEnabled = true
        return true
    }

    @discardableResult
    func saveDeskSetup(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, deskSetups.count < 8, previewPaper == nil else { return false }
        let setup = DeskSetup(name: String(trimmed.prefix(32)), textureID: textureID,
                              intensity: intensity, grainScale: grainScale, grainStrength: grainStrength,
                              matteStrength: matteStrength)
        guard setup.hasValidSettings, paperExists(id: textureID) else { return false }
        deskSetups.append(setup)
        return true
    }

    func overlayIsVisible(on displayID: String, frontmost bundleID: String?) -> Bool {
        !excludedDisplays.contains(displayID) && !isComparingOriginal
            && (previewPaper != nil || (shouldShowOverlay && appRuleAllows(frontmost: bundleID)))
    }

    var texture: TexturePreset {
        if let custom = customPapers.first(where: { $0.id == textureID }) {
            return TexturePreset(custom: custom)
        }
        return TexturePreset.preset(id: textureID)
    }

    /// What the overlay windows should render right now: a live Paper Mill
    /// draft when one is being previewed, otherwise the selected texture.
    var effectiveTexture: TexturePreset {
        if let previewPaper { return TexturePreset(custom: previewPaper) }
        return texture
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
        static let matteStrength = "matteStrength"
        static let appRuleMode = "appRuleMode"
        static let ruleApps = "ruleApps"
        static let customPapers = "customPapers"
        static let deskSetups = "deskSetups"
    }

    private let defaults: UserDefaults
    private var snoozeTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        intensity = defaults.object(forKey: Keys.intensity) as? Double ?? 0.22
        textureID = defaults.string(forKey: Keys.texture) ?? TexturePreset.all[0].id
        excludedDisplays = Set(defaults.stringArray(forKey: Keys.excluded) ?? [])
        hideFromCapture = defaults.bool(forKey: Keys.hideFromCapture)
        grainScale = defaults.object(forKey: Keys.grainScale) as? Double ?? 1.0
        grainStrength = defaults.object(forKey: Keys.grainStrength) as? Double ?? 1.0
        matteStrength = defaults.object(forKey: Keys.matteStrength) as? Double ?? 0.0
        appRuleMode = AppRuleMode(rawValue: defaults.string(forKey: Keys.appRuleMode) ?? "") ?? .everywhere
        ruleApps = defaults.data(forKey: Keys.ruleApps)
            .flatMap { try? JSONDecoder().decode([RuleApp].self, from: $0) } ?? []
        customPapers = defaults.data(forKey: Keys.customPapers)
            .flatMap { try? JSONDecoder().decode([CustomPaper].self, from: $0) } ?? []
        deskSetups = defaults.data(forKey: Keys.deskSetups)
            .flatMap { try? JSONDecoder().decode([DeskSetup].self, from: $0) }
            .map { Array($0.filter(\.hasValidSettings).prefix(8)) } ?? DeskSetup.starters

        // Recover older preferences written by non-finite automation input.
        intensity = intensity.isFinite ? min(max(intensity, 0.05), 0.45) : 0.22
        grainScale = grainScale.isFinite
            ? [0.5, 1, 2, 4].min(by: { abs($0 - grainScale) < abs($1 - grainScale) }) ?? 1 : 1
        grainStrength = grainStrength.isFinite ? min(max(grainStrength, 0.25), 2) : 1
        matteStrength = matteStrength.isFinite ? min(max(matteStrength, 0), 1) : 0
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
