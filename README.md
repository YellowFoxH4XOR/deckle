# Deckle

[![Latest release](https://img.shields.io/github/v/release/YellowFoxH4XOR/deckle?label=release&color=B34A22)](https://github.com/YellowFoxH4XOR/deckle/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/YellowFoxH4XOR/deckle/total?color=191713)](https://github.com/YellowFoxH4XOR/deckle/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Universal](https://img.shields.io/badge/universal-Apple%20Silicon%20%2B%20Intel-555)

**[projects.akshatkatiyar.com/projects/deckle](https://projects.akshatkatiyar.com/projects/deckle/)**

A free, open-source macOS menu bar app that lays a subtle **paper-grain texture over your entire screen**, making long reading and writing sessions feel more like paper than glass. Choose a built-in paper, tune it, or blend and preview your own before saving.

![Deckle toggling its paper texture over a web page](docs/deckle-demo.gif)

> If Deckle makes your screen nicer, [a star](https://github.com/YellowFoxH4XOR/deckle) helps other people find it ⭐

*A deckle is the wooden frame used in hand papermaking — it leaves behind the soft, feathered "deckle edge" that marks real handmade paper.*

Not a calibrated blue-light filter — a *matte texture* overlay. The grain breaks up the perfectly uniform backlight glow that makes screens feel harsh, while every pixel of your work stays interactive because the overlay is fully click-through. Paper Mill reports estimated blue-channel reduction and contrast retention as design guidance, not a medical claim.

## At a glance

<table>
  <tr>
    <td width="46%" align="center"><img src="docs/menu.png" alt="Deckle's menu-bar popover with live status, intensity, and paper cards" width="360"></td>
    <td width="54%" align="center"><img src="docs/paper-mill.png" alt="Paper Mill editor with live screen preview and eye-comfort guidance" width="420"></td>
  </tr>
  <tr>
    <td align="center"><strong>Everything at a glance.</strong><br><sub>Status, intensity, quick controls, and a scrollable paper library.</sub></td>
    <td align="center"><strong>Preview before you commit.</strong><br><sub>Blend a paper on the real display, inspect its contrast, then create it.</sub></td>
  </tr>
</table>

## Features

- **18 built-in paper textures** in three families:
  - *Papers* — Soft Wove, Rice Paper, Laid Cotton, Newsprint, Cold Press, Artist Canvas, Felt Side, Frost Glassine
  - *Warm & tinted* — Foxed Amber, Bookcloth, Recycled Kraft, Plum Kozo, Rose Quartz, Sage Press, Nordic Sky
  - *Dark* — Ink Stone, Midnight Slate, Espresso
- **Searchable paper library** — search names, descriptions, IDs, and material terms; filter by light, dark, or custom papers; use the edge fade and arrow to browse the compact carousel. Opening All Papers or searching resizes the menu immediately to fit its content
- **Paper Mill with live screen preview** — tune tint, wash, weave, and blotch against your actual desktop before creating or saving the paper
- **Comfort guidance** — see contrast retention, estimated brightness and blue-channel reduction, tint temperature, pattern load, and four starting recipes: Focus, Reading, Paper, and Night
- **Paper portability** — export custom papers as JSON, import them later, or install shared recipes from the [community papers repo](https://github.com/YellowFoxH4XOR/deckle-papers)
- **Intensity and grain controls** — intensity from 5–45%, grain size from Fine to Grainy, and independent grain strength
- **Global hotkey** — ⌥⌘P toggles the texture from any app
- **In-app updates** — Deckle checks GitHub Releases daily and surfaces a notification with one-click or automatic installation
- **Per-app rules** — hide the paper in chosen apps ("Except…") or show it only in chosen apps ("Only…")
- **Automation** — `deckle://` URL commands work from Shortcuts, Raycast, Alfred, cron, or Terminal
- **Capture privacy** — optionally hide the texture from screenshots and screen recordings while it stays visible to you
- **Snooze** for 15 min, 30 min, 1 hour, or 2 hours, then resume automatically
- **Multi-monitor support** with per-display inclusion
- **Launch at login**
- **Click-through and lightweight** — the texture is one small tiled image; Deckle uses approximately 0% CPU at rest
- **Menu-bar first** — no Dock icon or app-switcher entry; Paper Mill and Community Papers open only when requested

<p align="center"><img src="docs/search.png" width="520" alt="Deckle search showing three matching dark paper textures"></p>
<p align="center"><sub>Search switches directly to a full results grid; clearing it restores the status dashboard.</sub></p>

## Install

### Homebrew

```sh
brew tap yellowfoxh4xor/tap
brew trust yellowfoxh4xor/tap   # Homebrew 6+ asks once for third-party taps
brew install --cask deckle
```

### Download

Grab the DMG from the [latest release](https://github.com/YellowFoxH4XOR/deckle/releases/latest), open it, and drag Deckle into Applications. The app is signed with a Developer ID and notarized by Apple, so it launches without any Gatekeeper warning.

### Build from source

Requires Xcode command line tools, macOS 13+:

```sh
git clone https://github.com/<you>/deckle.git
cd deckle
make install    # builds, copies Deckle.app to /Applications, and launches
```

Or `make run` to try it from `dist/` without installing. Look for the paper-sheet icon in your menu bar.

## How it works

- Deckle owns one borderless, transparent `NSWindow` per display at `.screenSaver` level. Each window ignores mouse events, joins every Space, and tiles one small paper image through Core Animation, so memory does not grow with display resolution.
- Current papers use a deterministic **spectral renderer**: a random-phase, Hermitian-symmetric frequency field is synthesized with Accelerate/vDSP, inverse transformed into seamless grain, then layered with woven fibers and sparse flecks. Older custom papers retain the original value-noise renderer for byte-compatible output.
- The resulting 256×256-point tile contains both the tint wash and grain. The intensity control changes only the overlay window's `alphaValue`; identical render inputs reuse bounded caches.
- Paper Mill previews an unsaved draft through the same overlay windows used by saved papers. Preview state is transient, respects excluded displays, and is torn down when the editor closes or the draft is cancelled.
- **Energy design:** after setup, the retained-mode overlay renders nothing per frame. Update checks use `NSBackgroundActivityScheduler`; ordinary overlay changes are coalesced, and Paper Mill draft pushes are debounced to avoid regenerating spectral fields for every slider event.

## Automation

Anything that can open a URL can drive Deckle — Shortcuts' "Open URL" action, `open` in Terminal, Raycast, Alfred, cron:

```
deckle://on | off | toggle
deckle://snooze?minutes=30      deckle://resume
deckle://texture?name=Ink%20Stone
deckle://intensity?percent=25
deckle://grain?size=2&strength=1.2
```

Examples: a Shortcuts personal automation "At sunset → Open URL `deckle://on`" gives you circadian scheduling; "When Work Focus turns on → `deckle://texture?name=Soft%20Wove`" pairs papers with contexts.

## Development

```sh
swift run            # run unbundled (dev)
make app             # build dist/Deckle.app
make clean
```

No dependencies; pure Swift + AppKit + SwiftUI.

## Roadmap

- Battery auto-disable & Low Power Mode awareness
- Built-in sunset scheduling (today: use a Shortcuts automation with `deckle://on`)

## Contributing

The easiest PR: [share a paper recipe](https://github.com/YellowFoxH4XOR/deckle-papers) — 10 lines of JSON, no Swift needed. For code, see [CONTRIBUTING.md](CONTRIBUTING.md) and the [good first issues](https://github.com/YellowFoxH4XOR/deckle/labels/good%20first%20issue). Questions and ideas → [Discussions](https://github.com/YellowFoxH4XOR/deckle/discussions).

## License

[MIT](LICENSE)
