# Quiet reading presets: evidence and design

Research checked 16 September 2026. These are appearance presets, not clinically validated treatments for eye strain.

## What the evidence supports

- Preserve text/background contrast. W3C specifies 4.5:1 for ordinary text and 3:1 for large text. These are accessibility criteria, not eye-health scores. An overlay cannot guarantee that every underlying app meets them. [W3C: Contrast Minimum](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum)
- Texture is not inherently better for reading. A study of textured backgrounds found that texture affected search-time readability at low text contrast, with the effect depending on spatial frequency. It did not test Deckle or clinical eye strain. Our inference is to offer much lower-amplitude grain and a completely uniform option. [Scharff et al., 2000](https://pubmed.ncbi.nlm.nih.gov/12238520/)
- Avoid a large brightness mismatch between the screen and surroundings. Room lighting and reflected glare matter; adjust the display and workspace together. A software overlay cannot remove physical reflections from glass. [OSHA: Workstation Environment](https://www.osha.gov/etools/computer-workstations/workstation-environment)
- Warmer is a preference, not proof of protection. A Cochrane review found blue-light-filtering spectacle lenses may not reduce short-term computer eye strain; sleep results were uncertain. That review concerns glasses, not software overlays, and does not directly establish the effect of Deckle. We do not market an amber preset as an eye-health or sleep treatment. [Cochrane, 2023](https://www.cochrane.org/evidence/CD013244_blue-light-filtering-spectacle-lenses-visual-performance-macular-back-part-eye-protection-and)
- Dark mode is not universally more readable. A controlled proofreading study found better performance with dark text on light backgrounds under its test conditions. Keep light and dark use cases available; do not force a dark-screen default. [Piepenbrock et al., 2014](https://pubmed.ncbi.nlm.nih.gov/25135324/)

## Implemented collection

| Preset | Design intent |
| --- | --- |
| Clear Veil | Uniform neutral dimming with zero visible grain; the simplest starting point. |
| Book Cream | Restrained warm tint with very low grain amplitude; no laid lines or canvas weave. |
| Quiet Gray | Near-neutral gray with a faint fine texture, for people who want some material character. |
| Evening Shade | Stronger, slightly warm dimming with minimal texture; not a sleep or blue-light claim. |

The original 22 papers remain available unchanged. The four new recipes use stable seeds and the existing v3 engine, bringing the library to 26. They appear first in the library; search for `quiet reading` to isolate them. New installations default to Clear Veil. Existing saved selections and persisted desk setups are retained. The default Read, Write, and Unwind setups now point to Book Cream, Clear Veil, and Evening Shade respectively.

Quiet collection swatches show a fixed 22% sample instead of the legacy boosted texture preview. A swatch is not a live reading of the current screen. The real overlay continues to follow the intensity and grain controls.

## Rendered-tile measurements

At 22% intensity, 1× grain size, 1× grain strength, and 1× backing scale:

| Preset | White luminance reduction | Grain luminance SD | Gray-on-white contrast, worst sampled pair | Light-on-dark contrast, worst sampled pair |
| --- | ---: | ---: | ---: | ---: |
| Clear Veil | 5.22% | 0.0000% | 5.11:1 | 9.28:1 |
| Book Cream | 4.84% | 0.1653% | 4.94:1 | 8.98:1 |
| Quiet Gray | 7.53% | 0.1154% | 5.01:1 | 9.00:1 |
| Evening Shade | 17.64% | 0.0552% | 4.96:1 | 8.45:1 |

Soft Wove's grain luminance SD was 2.7537% under the same model: the three textured additions reduce this engineering measure by approximately 94–98%. That is **not** a measured reduction in eye strain. SD measures variation across an otherwise uniform white sample, not overall luminance reduction.

Method: sample the production RGBA composite tile, apply window opacity using premultiplied source-over in sRGB, and calculate linear-light relative luminance. Light-mode samples use sRGB gray 0.42 on white; dark-mode samples use 0.8 on 0.1333. Contrast uses conservative independent foreground/background extrema across the tile, not just mean colors. Automated tests repeat the contrast checks at 1× and 2× backing scales. These values do not represent physical display nits, ambient reflections, or calibrated monitor measurements. Other app colors and higher intensity or grain settings can produce different results.

## Verification

```sh
swift test --filter ReadingPresetTests
DECKLE_RENDER_DIR="$PWD/docs" swift test
make app UNIVERSAL=1
```

The comparison images `reading-proof-light.png` and `reading-proof-dark.png` render the same text under the actual production overlay tiles at 22%, alongside bare screen and original Soft Wove. They are native view renders, not photographs of a monitor or live menu-bar captures. Live menu-bar verification remains limited by the native automation tool's inability to access the status-item popup.
