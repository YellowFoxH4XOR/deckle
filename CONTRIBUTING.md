# Contributing to Deckle

Thanks for considering it! Deckle is a small, focused app — contributions that keep it small and focused are the most welcome kind.

## The easiest contribution: share a paper

No Swift required. Blend a paper in the app (**My Papers → New…**), right-click → **Export…**, and PR the JSON to [deckle-papers](https://github.com/YellowFoxH4XOR/deckle-papers). Same-day review.

## Building

```sh
git clone https://github.com/YellowFoxH4XOR/deckle.git
cd deckle
swift run        # run unbundled for development
make app         # build dist/Deckle.app (ad-hoc signed)
```

No dependencies — pure Swift + AppKit/SwiftUI, built with SPM. macOS 13+, Xcode command line tools.

## Making changes

- `main` is protected: branch → PR. CI isn't required to pass for docs-only changes, but the app must build (`swift build -c release`).
- Look at [`good first issue`](https://github.com/YellowFoxH4XOR/deckle/labels/good%20first%20issue) for curated starting points, or open a Discussion before larger work so we agree on direction first.
- Code style: match what's around you. Comments explain *constraints*, not what the next line does.
- One feature per PR. Screenshots for UI changes help a lot.

## Architecture in 60 seconds

- `TexturePreset.swift` — texture recipes (data). `TextureRenderer.swift` — tileable value-noise engine that renders them.
- `OverlayWindow/OverlayController` — one click-through window per display; the texture is a CALayer pattern color (retained-mode — nothing renders per frame).
- `AppState` — all settings, persisted to UserDefaults. `MenuView` — the menu bar popover UI.
- `PaperMill/CommunityBrowser` — custom papers and the shared-recipe browser. `URLCommands` — the `deckle://` automation surface.

## Releases

Maintainer tags `vX.Y.Z` → CI builds a universal DMG, signs, notarizes, staples, and publishes. Users auto-update in-app.

## License

MIT. By contributing you agree your contributions are MIT-licensed too.
