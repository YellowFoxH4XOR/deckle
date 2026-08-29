# AGENTS.md

Deckle is a focused macOS menu-bar app that overlays deterministic paper texture on every display. Keep it small, native, energy-efficient, and compatible with macOS 13.

## Project facts

- Language: Swift 5.9 package
- UI: SwiftUI plus AppKit where window behavior matters
- Minimum platform: macOS 13
- Dependencies: none outside Apple frameworks
- Product shape: menu-bar accessory app; no Dock or app-switcher entry
- Build system: Swift Package Manager plus the root `Makefile`

Run commands from this repository root. Do not assume tools or dependencies from sibling projects in the parent workspace.

## Commands

```sh
swift build                         # Debug compile
swift test                          # Full test suite
swift test --filter PaperComfortTests
swift run                           # Unbundled development run
make app                            # Release build + ad-hoc signed dist/Deckle.app
make build UNIVERSAL=1              # arm64 + x86_64 release compile
make dmg                            # Local DMG
```

Before shipping a code change, run `swift test`. For release-sensitive changes, also run `make build UNIVERSAL=1`: the release workflow uses Xcode 15.4 and builds both architectures, which can expose actor-isolation errors that a local single-architecture build misses.

## Source map

| Area | Files | Responsibility |
|---|---|---|
| App entry and state | `DeckleApp.swift`, `AppState.swift` | MenuBarExtra, application lifecycle, persisted settings, transient preview state |
| Overlay | `OverlayController.swift`, `OverlayWindow.swift` | One click-through retained-mode window per display |
| Rendering | `TexturePreset.swift`, `TextureRenderer.swift` | Versioned texture recipes, spectral/legacy engines, bounded caches |
| Main menu | `MenuView.swift`, `HeroCardView.swift`, `PresetCardView.swift`, `QuickControlsView.swift`, `FeaturePromoCard.swift` | Status, search, paper library, controls, discovery |
| Paper creation | `PaperMill.swift`, `PaperComfort.swift` | Custom paper editing, live preview, comfort estimates, import/export |
| Community and updates | `CommunityBrowser.swift`, `UpdateManager.swift` | Community paper index, download/install, GitHub release updates |
| Automation | `HotKey.swift`, `URLCommands.swift` | Global shortcut and `deckle://` commands |
| Assets and packaging | `Icons.swift`, `Support/Info.plist`, `scripts/GenerateIcon.swift`, `Makefile` | Menu glyph, app metadata, app bundle, DMG |

## Architectural invariants

### State and persistence

- `AppState.shared` is the single source of truth for user-facing settings.
- Persistent properties write through to `UserDefaults` in `didSet`; keep keys stable unless a migration is implemented.
- Transient state must not be persisted. `previewPaper` exists only while Paper Mill previews an unsaved draft.
- `texture` means the saved selection. `effectiveTexture` may temporarily resolve to the Paper Mill preview. Do not conflate them in menu chrome or automation.
- Keep `shouldShowOverlay` tied to enabled/snoozed state. Preview visibility is handled separately by `OverlayController`.

### Overlay windows

- Maintain one `OverlayWindow` per connected display.
- Overlay windows must remain borderless, transparent, click-through, retained-mode, and at `.screenSaver` level.
- Preserve `canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, and `.ignoresCycle` behavior.
- Per-display exclusions always win, including during Paper Mill preview.
- A Paper Mill preview may override enabled, snoozed, and app-rule visibility so an unsaved paper can be judged on screen.
- Do not allocate display-sized texture bitmaps. `TextureView` must continue using a small tiled layer pattern.

### Renderer compatibility and performance

- Renderer versions are a compatibility boundary:
  - `.legacy` must remain byte-compatible for version-less historical custom papers.
  - `.spectral` is used by built-ins and newly created papers.
- Stable seeds must round-trip through JSON. Never use Swift `hashValue` for deterministic output.
- Preserve Hermitian symmetry, inverse-FFT normalization, seamless wrapping, and backing-scale behavior in the spectral engine.
- Renderer caches are bounded LRUs and intentionally main-thread-only. Do not call them concurrently without redesigning synchronization.
- Cache keys must include every render-relevant input and exclude irrelevant metadata such as a paper name.
- Avoid uncached 2x spectral rendering directly in a parent SwiftUI body that observes unrelated state. Isolate expensive thumbnails in equatable child views, use 1x while dragging, and debounce full overlay pushes.
- Any renderer change needs deterministic tests. Legacy changes also need the pinned byte hash to remain unchanged unless compatibility is intentionally broken.

### Paper Mill

- A draft is not saved until Create or Save is pressed.
- `compose(from:)` must create a fresh ID and seed; cancelling a duplicated built-in must leave `customPapers` unchanged.
- Live preview must render through the production overlay pipeline, not a separate approximation.
- Clear `AppState.previewPaper` on every exit path: Stop Preview, Cancel, Save, Delete, programmatic close, and `windowWillClose`.
- Paper Mill window state and the menu's Open/Close label must agree even when the window is miniaturized.
- Position the editor against the actual MenuBarExtra content window only. Never identify it using generic `Panel` or `StatusBar` class-name matches.
- Clamp window placement to the owning screen's `visibleFrame`; display coordinates may be negative.
- `PaperComfort` is design guidance, not a medical claim. Keep labels precise: contrast retention, luminance change, blue-channel reduction, tint temperature, and pattern load.

### Menu and secondary windows

- Keep the popover compact and usable at 370 points wide.
- Search operates across built-in and custom papers. Normalize whitespace and search render-independent metadata without hiding the controls drawer.
- Category filters must include matching custom papers and must reset when their controls become hidden in compact mode.
- Horizontal carousels need an explicit overflow affordance; do not show a fade or paging arrow when content fits.
- Preserve stable entry points for New, Import, and Community Papers. A dismissible promo card is not sufficient navigation.
- `MenuDismiss` may dismiss MenuBarExtra/popover content only. It must not order out `NSColorPanel`, `NSStatusBarWindow`, or arbitrary nonactivating panels, and it must never send a generic `performClose:` down the responder chain.
- AppKit and observable UI singletons are `@MainActor`. Stored callback closures are not automatically actor-isolated under the Xcode 15 release compiler; hop explicitly with `Task { @MainActor in ... }` before calling them.

## Testing expectations

Tests live in `Tests/DeckleTests` and use XCTest with `@testable import Deckle`.

Add or update tests when changing:

- renderer determinism, resolution, normalization, caches, or legacy fidelity
- custom paper coding, engine versions, or seed behavior
- comfort calculations, clamping, grade thresholds, or recipe identity preservation
- any pure state transition that has a deterministic test seam

Prefer observable contract tests over source-shape tests. Use tolerances for floating-point values and fixed seeds for renderer output.

UI and AppKit window behavior often lack a useful unit-test seam. For those changes:

1. Build `dist/Deckle.app` with `make app`.
2. Launch the bundled app, not only `swift run`.
3. Exercise the changed path through the real menu-bar UI.
4. Verify the resulting accessibility state and visible window geometry.
5. Capture updated screenshots for meaningful UI changes.

## Code style

- Match the surrounding Swift style: four-space indentation, explicit names, small focused helpers.
- Prefer boring code and existing patterns over new abstractions.
- Comments explain constraints, compatibility, or non-obvious lifecycle behavior—not the next statement.
- Keep AppKit operations on the main actor.
- Avoid force unwraps for external data and window discovery.
- Imported paper JSON and community data are untrusted. Keep numeric clamping, path sanitization, and fixed-host HTTPS restrictions intact.
- Do not suppress errors or warnings to hide a root cause.
- Do not add dependencies for behavior available in Foundation, AppKit, SwiftUI, CoreGraphics, Combine, ServiceManagement, or Accelerate.

## Documentation

- Update `README.md` when visible behavior, installation, automation, or architecture changes.
- UI screenshots live under `docs/`; use descriptive alt text and avoid user-specific or private content.
- Keep `CONTRIBUTING.md` concise and consistent with this guide.

## Pull requests

- `main` is protected: use a focused branch and PR for normal changes.
- Keep one coherent feature or fix per PR.
- Include the exact verification commands and results.
- Include screenshots for UI work.
- Do not commit `.build/`, `build/`, `dist/`, local preferences, exported private papers, or signing credentials.

## Releases

Releases are tag-driven through `.github/workflows/release.yml`.

1. Update both `CFBundleShortVersionString` and monotonically increasing `CFBundleVersion` in `Support/Info.plist`.
2. Run `plutil -lint Support/Info.plist`, `swift test`, and `make build UNIVERSAL=1`.
3. Commit the version bump.
4. Create an annotated `vX.Y.Z` tag with message `Deckle X.Y.Z`.
5. Push the commit and tag.
6. Verify the workflow builds the universal DMG, signs, notarizes, staples, generates the checksum, and publishes both assets.

Never move an already published release tag. If a tag-triggered workflow fails before publishing assets, choose explicitly between correcting the unpublished tag and issuing a new patch version.
