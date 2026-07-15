import AppKit

/// Automation surface: `deckle://` commands, usable from Shortcuts ("Open URL"
/// action), Terminal (`open "deckle://toggle"`), Raycast, Alfred, cron —
/// anything that can open a URL. This is how scheduling works without Deckle
/// growing its own scheduler UI: let the OS automate us.
///
///   deckle://on                     enable the texture
///   deckle://off                    disable the texture
///   deckle://toggle                 flip it
///   deckle://snooze?minutes=30      snooze (default 30)
///   deckle://resume                 cancel a snooze
///   deckle://texture?id=soft-wove   switch texture (id or exact name)
///   deckle://intensity?percent=25   set intensity (5–45)
///   deckle://grain?size=2&strength=1.2
enum URLCommands {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "deckle" else { return }
        let state = AppState.shared
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]

        switch url.host?.lowercased() {
        case "on":
            state.cancelSnooze()
            state.isEnabled = true
        case "off":
            state.isEnabled = false
        case "toggle":
            if state.shouldShowOverlay {
                state.isEnabled = false
            } else {
                state.cancelSnooze()
                state.isEnabled = true
            }
        case "snooze":
            let minutes = params["minutes"].flatMap(Int.init) ?? 30
            state.snooze(minutes: min(max(minutes, 1), 24 * 60))
        case "resume":
            state.cancelSnooze()
        case "texture":
            // Normalize so "ink-stone", "Ink Stone", and "inkstone" all match.
            func normalize(_ s: String) -> String {
                s.lowercased().filter(\.isLetter)
            }
            let query = normalize(params["id"] ?? params["name"] ?? "")
            guard !query.isEmpty else { return }
            if let preset = TexturePreset.all.first(where: {
                normalize($0.id) == query || normalize($0.name) == query
            }) {
                state.textureID = preset.id
            } else if let custom = state.customPapers.first(where: {
                normalize($0.id) == query || normalize($0.name) == query
            }) {
                state.textureID = custom.id
            }
        case "intensity":
            if let percent = params["percent"].flatMap(Double.init) ?? params["value"].flatMap(Double.init) {
                state.intensity = min(max(percent / 100, 0.05), 0.45)
            }
        case "grain":
            if let size = params["size"].flatMap(Double.init) {
                // Snap to the picker's detents so UI and URL agree.
                state.grainScale = [0.5, 1.0, 2.0, 4.0].min {
                    abs($0 - size) < abs($1 - size)
                } ?? 1.0
            }
            if let strength = params["strength"].flatMap(Double.init) {
                state.grainStrength = min(max(strength, 0.25), 2.0)
            }
        default:
            break
        }
    }
}
