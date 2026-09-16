# Deckle 1.9.0 release plan

Target: Deckle 1.9.0, build 20. Deckle 1.8.0, build 19 was the latest
published release when this candidate was prepared; the new build number exceeds
every published build.

## Scope

- Your desk and Paper library navigation, revised material samples and styling.
- Saved desk setups and temporary original-screen comparison.
- Clear Veil, Book Cream, Quiet Gray, and Evening Shade presets.
- Matte finish slider, with persisted strength.
- Search normalization, invalid numeric input recovery, imported tint classification.
- Packaging fix: resolve the release binary path from SwiftPM instead of copying
  from a toolchain-specific directory that can contain a stale executable.

## Cleanup completed

Moved the obsolete local 1.6.0 DMG, generated Ruby LSP directory, and
`Sources/.DS_Store` to a temporary recovery directory outside this checkout.
Added a repository ignore rule for Ruby LSP output.

Keep source, tests, design specifications, research, and visual proof files.
Keep current build caches and `dist/Deckle.app` for local verification; these are
already ignored and must not be committed. Keep older tracked screenshots until
replacement documentation and external image references have been reviewed.

## Release blockers and implementation checks

- Matte is persisted in desk setups, with missing values from older setup JSON
  migrating to zero. The UI reports the actual rounded percentage, including 0%.
- Matte has deterministic output and cache tests; the field and grain-tile caches
  exclude matte because it only changes the final tint composite.
- Paper Mill appearance estimates explicitly cover the tint wash and exclude the
  separate Matte finish control.
- Validate appearance on light and dark content across presets and intensity
  settings. The current operation blends the tint toward gray; it is not
  content-aware highlight processing and cannot change physical glass reflections.
- Native desk review renders include the Matte finish control and the README
  identifies them as isolated renders; older demo/editor imagery is not presented
  as the current studio menu.
- The bundled candidate was exercised through library search, controls, setup
  save/restart/remove, compare/dismiss, snooze, app rules, display controls, and
  Paper Mill preview/close. Live captures verified the 370-point menu, accessible
  labels, and Paper Mill placement on the built-in Retina display. No secondary
  display was connected; bounded and negative-coordinate geometry remain covered
  by `MenuPopoverTests`.

## Verification and release sequence

1. Resolve blockers, review the complete diff, and run `swift test` and
   `make build UNIVERSAL=1`. Verify supported macOS deployment targets and both
   binary slices. Exercise `make app UNIVERSAL=1` from a clean build environment
   to ensure the packaging fix works on the release runner as well as locally.
2. `.github/workflows/release.yml` runs on `macos-14` with Xcode 15.4 selected
   explicitly and validates the plist, tag/version agreement, and full test suite
   before packaging. Developer ID and notarization secrets are configured; never
   print their values to verify availability.
3. Prepare release notes describing the user-visible changes and the matte
   control's actual behavior. Submit the focused branch through a PR to protected
   main, including exact verification results and screenshots.
4. Once ready to publish, update both bundle version fields and run
   `plutil -lint Support/Info.plist`, `swift test`, and
   `make build UNIVERSAL=1` against the final candidate. Commit the version bump
   through the protected-branch process.
5. Create the annotated version tag on the approved release commit and push it.
   This triggers publication; it is not part of this preparation request.
6. Verify the workflow builds the universal DMG, signs, notarizes, staples,
   creates its checksum, and publishes both assets. Download and smoke-test the
   published bundle and update path. Never move an already published tag.

## Validation record

- `plutil -lint Support/Info.plist` and `git diff --check`: passed for the 1.9.0 candidate.
- `swift test`: 77 tests passed; the 2 opt-in rendering tests also passed separately.
- `make build UNIVERSAL=1` and `make app UNIVERSAL=1`: passed; the bundled binary
  contains both arm64 and x86_64 slices and its signature verifies.
- Live bundled-app validation passed. It found and fixed comparison remaining active
  after leaving Your desk; tab, controls, Paper Mill, and menu-dismiss paths now
  restore the saved overlay. The user's preferences were backed up and restored
  byte-for-byte after the smoke test.
