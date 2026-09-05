---
name: Deckle
description: A quiet, tactile macOS control surface for making screens feel like paper.
colors:
  brand-rust: "#B34A22"
  action-blue: "#007AFF"
  success-green: "#34C759"
  warning-orange: "#FF9500"
  danger-red: "#FF3B30"
  promo-purple: "#AF52DE"
  window-light: "#F5F5F7"
  surface-light: "#FFFFFF"
  label-light: "#1D1D1F"
  secondary-label-light: "#6E6E73"
  hairline-light: "#00000014"
  window-dark: "#1C1C1E"
  surface-dark: "#2C2C2E"
  label-dark: "#F5F5F7"
  secondary-label-dark: "#AEAEB2"
  hairline-dark: "#FFFFFF14"
typography:
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.25
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.35
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.25
  micro:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "10px"
    fontWeight: 500
    lineHeight: 1.2
  mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "10px"
    fontWeight: 600
    lineHeight: 1.2
rounded:
  metric: "4px"
  badge: "6px"
  texture: "8px"
  icon: "10px"
  control: "12px"
  panel: "14px"
  drawer: "16px"
  hero: "18px"
  capsule: "999px"
spacing:
  hairline: "2px"
  compact: "4px"
  control: "6px"
  item: "8px"
  group: "10px"
  section: "12px"
  panel: "14px"
  card: "16px"
  window: "18px"
components:
  button-primary:
    backgroundColor: "{colors.action-blue}"
    textColor: "{colors.surface-light}"
    typography: "{typography.body}"
    rounded: "{rounded.capsule}"
    padding: "6px 10px"
    height: "36px"
  button-icon:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.label-light}"
    rounded: "{rounded.capsule}"
    size: "36px"
  search-field:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.label-light}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "8px 10px"
    height: "40px"
  hero-card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.label-light}"
    rounded: "{rounded.hero}"
    padding: "16px"
  paper-card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.label-light}"
    rounded: "{rounded.control}"
    padding: "8px"
    width: "108px"
  filter-chip:
    backgroundColor: "{colors.window-light}"
    textColor: "{colors.label-light}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "4px 10px"
  filter-chip-selected:
    backgroundColor: "{colors.brand-rust}"
    textColor: "{colors.surface-light}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "4px 10px"
---

# Design System: Deckle

## Overview

**Creative North Star: "The Quiet Paper Studio"**

Deckle is opened briefly while someone is reading, writing, or working across one or more displays. Its controls should feel like well-kept tools on a calm desk: familiar, precise, tactile, and ready to disappear as soon as the paper is chosen.

The interface is a restrained macOS product surface. System materials and semantic colors provide adaptation; one accent identifies selection and primary action. Texture is the subject, not decoration. Dense controls remain legible without turning the popover into a dashboard.

Deckle rejects ornamental glassmorphism, neon utility palettes, oversized marketing typography, nested card stacks, and motion that delays a task.

**Key Characteristics:**

- System-native and immediately understandable
- Quiet neutral surfaces with one active accent
- Paper previews as the dominant visual material
- Compact controls with explicit labels and state
- Focused modes instead of stacking every section vertically
- Fast, interruptible transitions with no bounce

**The Focused Surface Rule.** When a task expands, the competing summary surface leaves. All Papers hides the hero card; search hides summary content; Compact restores it.

**The Honest Material Rule.** The system window may use native translucency. Content surfaces inside it are opaque or strongly tonal. Empty translucent regions are forbidden.

## Colors

The palette is adaptive and restrained. In SwiftUI, system semantic colors remain the runtime source of truth. The fixed light and dark values above are cross-tool equivalents for documentation and generated components.

### Primary

- **Deckle Rust** (`brand-rust`): product identity, selected filters on branded surfaces, and documentation accents. It must not flood large regions.
- **Action Blue** (`action-blue`): Open Mill and explicit primary actions that need the standard macOS action signal.

### Secondary

- **Success Green** (`success-green`): active overlay state, successful checks, and healthy preview feedback.
- **Warning Orange** (`warning-orange`): snooze state and contrast guidance that needs attention but does not block saving.
- **Danger Red** (`danger-red`): destructive actions, update notification dots, and errors only.
- **Workshop Purple** (`promo-purple`): rare discovery prompts such as Paper Mill education, never core navigation.

### Neutral

- **Quiet Window** (`window-light`, `window-dark`): outer popover and secondary toolbar layer.
- **Paper Surface** (`surface-light`, `surface-dark`): hero, editor, search, and control surfaces.
- **Ink Label** (`label-light`, `label-dark`): primary text and active iconography.
- **Soft Graphite** (`secondary-label-light`, `secondary-label-dark`): descriptions, metadata, inactive labels, and help copy.
- **Hairline** (`hairline-light`, `hairline-dark`): one-pixel containment where tonal separation alone is insufficient.

**The One Active Accent Rule.** Accent color marks current selection, focus, or the primary action. Inactive controls stay neutral.

**The Semantic State Rule.** Green means active or successful, orange means caution or snoozed, and red means destructive, failed, or newly available. Never reuse those colors decoratively.

## Typography

**Display Font:** Apple system font
**Body Font:** Apple system font
**Label/Mono Font:** SF Mono for changing values and engine metadata

**Character:** Native, compact, and matter-of-fact. Weight and scale establish hierarchy; font changes do not.

### Hierarchy

- **Headline** (700, 19px, 1.2): selected paper name inside the hero card.
- **Title** (700, 15px, 1.25): panel and editor titles.
- **Body** (500, 13px, 1.35): buttons, status copy, paper names, and primary controls.
- **Label** (600, 11px, 1.25): section labels, chips, slider labels, and compact commands.
- **Micro** (500, 10px, 1.2): secondary explanations and metadata.
- **Mono** (600, 10px, 1.2): engine status, percentages, timers, and numerical readouts.

**The Stable Number Rule.** Every changing percentage, timer, count, and comfort metric uses monospaced or monospaced-digit typography so controls do not shift.

**The Native Voice Rule.** Buttons use sentence case and short verbs. Uppercase is reserved for terse engine metadata, never ordinary labels.

## Elevation

Deckle uses a hybrid of tonal layering and restrained ambient shadows. Surfaces are separated first by system background roles, then by a low-opacity hairline. Shadows indicate a surface that is physically above another surface, not decoration.

### Shadow Vocabulary

- **Control Lift:** `0 1px 2px rgba(0, 0, 0, 0.04)`. Circular toolbar controls and compact capsules.
- **Texture Lift:** `0 1px 3px rgba(0, 0, 0, 0.08)`. Circular texture preview against the hero surface.
- **Hero Lift:** `0 3px 8px rgba(0, 0, 0, 0.06)`. The primary status surface only.
- **Paging Lift:** `0 2px 4px rgba(0, 0, 0, 0.12)`. Floating carousel navigation over paper cards.

**The Ambient Only Rule.** Shadows remain diffuse and below 12% black. If an edge looks drawn or dirty, the shadow is too strong.

**The One Raised Hero Rule.** The hero may be raised. Inner metric groups and control drawers use tonal separation, not another large shadow.

## Components

### Popover Shell

- **Width:** fixed at 370 points.
- **Padding:** 14 points around the content.
- **Rhythm:** 12-point section spacing.
- **Sizing:** fit current vertical content. Variable modes must not leave stale window material below the footer.
- **Theme:** use `NSColor.windowBackgroundColor` and native appearance adaptation.

### Top Actions

- **Shape:** compact capsule for Open Mill; 36-point circles for notification and account actions.
- **Icon badge:** 22-point colored circle inside the Open Mill capsule.
- **State:** Open Mill changes to Close Mill while the editor exists. Notification color follows update status.
- **Elevation:** Control Lift.

### Search Field

- **Shape:** gently rounded field (12-point radius), 40-point target height.
- **Background:** control surface with an 8% semantic hairline.
- **Focus:** accent-colored icon and 50% accent hairline.
- **Behavior:** normalized whitespace; search immediately enters a focused results grid and removes the hero.

### Hero Status Surface

- **Shape:** 18-point radius with 16-point internal padding.
- **Content order:** engine metadata, texture identity, status, primary action, then intensity.
- **Preview:** 48-point circular live texture inside a 50-point holder.
- **Primary action:** 38-point capsule. Neutral while active; accent-filled when enabling or resuming.
- **Secondary action:** 38-point circular More control.
- **Numbers:** monospaced percentages and timers.

### Paper Cards

- **Width:** 108 points. Three cards plus two 8-point gaps must fit the popover content width.
- **Shape:** 12-point card radius and 8-point texture radius.
- **Internal padding:** 8 points.
- **Selection:** accent hairline and a subtle 9% accent wash. Do not rely on color alone; retain the checkmark.
- **Text:** one-line paper name and one-line material tag.

### Paper Library

- **Compact mode:** horizontal carousel with a trailing fade and floating arrow only when at least three cards overflow.
- **All Papers mode:** hide the hero and promo surfaces, show category chips, then a three-column vertical grid.
- **Expanded viewport:** row-aware fixed height, capped at 236 points.
- **Search viewport:** row-aware fixed height, capped at 360 points.
- **Window fit:** the popover shell uses current content height so Compact removes expanded grid space immediately.
- **Transition:** 200ms ease-out. No spring, bounce, or full-height slide.

### Filter Chips

- **Shape:** capsule, 4-point vertical and 10-point horizontal padding.
- **Unselected:** quiet neutral fill with primary text.
- **Selected:** current accent fill with contrasting text.
- **Behavior:** switching back to Compact resets hidden category state to All.

### Control Drawer

- **Outer shape:** 16-point radius with 12-point padding.
- **Inner control surface:** 14-point radius with 14-point padding.
- **Tabs:** horizontally scrollable capsules with full labels. A trailing fade communicates overflow.
- **Behavior:** remains reachable during search; opening All Papers closes it.

### Notifications

- **Shape:** 14-point tonal surface.
- **Leading symbol:** 34 to 36-point rounded badge.
- **State:** blue/accent for progress and availability, green for success, orange for failure, red only for the unread dot.
- **Dismissal:** remember the dismissed version, not a global boolean.

### Paper Mill

- **Window:** resizable, minimum 400 by 500 points; position beside the MenuBarExtra within the owning display's visible frame.
- **Preview:** 8-point rounded texture image with a subtle outline.
- **Primary control:** Preview on Screen is prominent and becomes Stop Preview while active.
- **Comfort readout:** compact two-column metric surface with monospaced numbers and a semantic grade chip.
- **Performance:** render thumbnail at 1x during adjustment and 2x when settled; debounce real-overlay updates.

## Do's and Don'ts

### Do:

- **Do** use the Apple system font and native semantic colors for application UI.
- **Do** keep the popover at 370 points with 14-point outer padding and 12-point section rhythm.
- **Do** give every vertical `ScrollView` inside MenuBarExtra a deterministic viewport height.
- **Do** hide the hero when All Papers or search becomes the primary task.
- **Do** use `.fixedSize(horizontal: false, vertical: true)` at the popover root when content height changes by mode.
- **Do** keep card dimensions explicit: 108-point paper cards, 8-point gaps, three columns.
- **Do** use 150 to 250ms state transitions with ease-out timing and no visible bounce.
- **Do** use monospaced digits for live percentages, countdowns, counts, and comfort metrics.
- **Do** use checkmarks, labels, or symbols alongside semantic color.
- **Do** show carousel fades and arrows only when content actually overflows.
- **Do** keep Paper Mill comfort language factual and non-medical.

### Don't:

- **Don't** use `.frame(maxHeight:)` alone for a flexible grid inside MenuBarExtra. It may collapse while the window keeps translucent empty space.
- **Don't** stack the hero, control drawer, and expanded library in one vertical state.
- **Don't** use decorative glassmorphism. Native window material is sufficient; content surfaces must remain readable and bounded.
- **Don't** nest cards inside cards. Use spacing, dividers, and tonal groups before another container.
- **Don't** use gradient text, neon accents, side-stripe borders, or oversized display typography.
- **Don't** use success, warning, or danger colors outside their semantic meaning.
- **Don't** hide a selected category when returning to Compact; reset it to All.
- **Don't** truncate control-tab labels to make them fit. Keep the tab row scrollable and signal overflow.
- **Don't** animate layout with spring bounce. Motion communicates a state change and then gets out of the way.
- **Don't** leave blank material below the footer after a mode transition. If that occurs, the sizing contract is broken.
