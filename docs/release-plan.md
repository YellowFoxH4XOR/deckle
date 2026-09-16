# Proposed Deckle 1.9.0 release

Status: preparation only. No version bump, commit, tag, push, or publication yet.
Current local metadata is 1.8.0, build 19. Propose 1.9.0, build 20 for
the new workflows and controls; verify remote release/tag history before assigning
the final version and ensure the build number exceeds every published build.

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
- Regenerate the native desk review renders so they include the matte control and
  review older demo/editor imagery for misleading UI or claims.
- Run the bundled app through library search, controls, setups, compare/dismiss,
  snooze, app rules, display exclusions, and Paper Mill preview lifecycle. Verify
  accessibility and geometry at 370 points and on a short/secondary screen.
  Capture current screenshots. Prior native view renders are not live UI evidence.

## Verification and release sequence

1. Resolve blockers, review the complete diff, and run `swift test` and
   `make build UNIVERSAL=1`. Verify supported macOS deployment targets and both
   binary slices. Exercise `make app UNIVERSAL=1` from a clean build environment
   to ensure the packaging fix works on the release runner as well as locally.
2. Review `.github/workflows/release.yml`: it currently runs on `macos-14` without
   explicitly selecting Xcode, runs no tests, and permits ad-hoc signing when
   signing secrets are absent. Add test/plist gates and validate intended compiler
   selection and Developer ID/notarization availability before publishing.
   Never print signing secrets to verify their availability.
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

- `plutil -lint Support/Info.plist`: passed during cleanup.
- `git diff --check`: passed after cleanup and plan changes.
- `swift test`: 71 tests reported, 2 opt-in rendering tests skipped, 0 failures.
- Current matte behavior: covered by deterministic unit tests; live bundled-app UI
  verification remains pending as described above.
