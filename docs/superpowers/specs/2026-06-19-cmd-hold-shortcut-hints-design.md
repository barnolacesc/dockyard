# Cmd-Hold Shortcut Hints — Design

**Date:** 2026-06-19
**Status:** Approved (brainstorm), pending implementation plan

## Summary

Add a keyboard-discovery aid: while the user holds **⌘**, small key badges fade in on
every actionable on-screen element, anchored to a corner of each (e.g. the Coding Agent
tab shows `⌘2`, a terminal tab shows `⌘3`, the Start/Rerun button shows `⌘⇧⏎`). Adding
**⇧** or **⌥** live-swaps each badge to the variant for that modifier combination. The
whole feature is gated by a new Settings toggle (default **on**).

The goal is learnability — surfacing the shortcuts that already exist (catalogued in
`HelpView`) right where the user is looking, instead of requiring a trip to the help pane.

## Goals

- Badges appear on actionable chrome the instant ⌘ is pressed (no hold delay).
- Badges update live as ⇧/⌥ are added, showing the matching variant of each shortcut.
- Cover four areas: workspace tab bar, workspace action buttons, sidebar, browser/editor
  controls.
- A Settings toggle turns the whole behavior on/off.
- Zero interference with existing shortcuts, the terminal, or focus — the feature only
  observes modifier state, never consumes events.

## Non-Goals

- No badges *inside* the Metal-rendered terminal surface (only the SwiftUI/AppKit chrome
  around it).
- No new shortcuts and no changes to existing keybindings or the menu commands.
- No changes to `HelpView`'s shortcut catalogue (it remains the canonical full reference).
- No hold-delay / debounce on activation (the user chose instant-on).

## Behavior

1. **Activation.** Setting on + ⌘ pressed → badges fade in immediately (~0.1s opacity
   transition).
2. **Progressive modifiers.** The currently-held combo (`⌘`, `⌘⇧`, `⌘⌥`) selects which
   badge each element shows. An element only renders a badge if it has an entry for the
   current combo; otherwise it shows nothing for that combo.
3. **Dismissal.** Badges disappear when any of: ⌘ is released, a non-modifier key is
   pressed (so a fired shortcut dismisses the brief flash), or the app resigns active.
4. **Instant-mode tradeoff.** Because there is no hold delay, badges flash briefly during
   ordinary ⌘-shortcut typing (e.g. ⌘C). Dismiss-on-keydown keeps this to a flash. This is
   an accepted consequence of the instant-on choice.

## Architecture

Three pieces, all new code in one file plus annotations on existing views.

### 1. `ShortcutHintController` — new `Sources/Views/ShortcutHints.swift`

A `@MainActor final class ... : ObservableObject` singleton, injected into the view tree as
an `environmentObject`. Published state:

- `isActive: Bool` — whether badges should currently render.
- `activeModifiers: NSEvent.ModifierFlags` — the exact held combo (always contains
  `.command` when active; may also contain `.shift` and/or `.option`).

It owns its event monitors, started once at launch (mirroring the existing
`NSEvent.addLocalMonitorForEvents` pattern in `AppDelegate.applicationDidFinishLaunching`):

- `.flagsChanged` monitor → feeds a pure reducer (see below) to update `isActive` /
  `activeModifiers`.
- `.keyDown` monitor → if active, sets `isActive = false`.
- `NSApplication.didResignActiveNotification` → `isActive = false`.

All monitors **return the event unmodified** (never `nil`), so nothing is consumed and the
terminal / shortcuts / focus are untouched even when the Ghostty `NSView` is first
responder.

The setting is read via `UserDefaults` (`dockyard.showShortcutHints`, default `true`); when
off, the reducer always yields `isActive = false`.

#### Pure reducer (unit-testable)

```
reduce(flags: NSEvent.ModifierFlags, enabled: Bool) -> (isActive, activeModifiers)
```

Normalizes flags to `[.command, .shift, .option]` ∩ event flags; active iff `enabled` and
`.command` present. Keeping this a free function (or static method) lets us test the state
logic without NSEvent plumbing.

### 2. Anchor-preference plumbing

- `struct ShortcutHint`: a small ordered map of `combo (ModifierFlags) → KeyBadge` where
  `KeyBadge` holds the symbols/keys to draw (reusing the `command`/`shift`/`option` SF
  Symbol + key-text styling from `HelpView.ShortcutRow`).
- `ShortcutHintAnchorKey: PreferenceKey` collecting `[ID: (Anchor<CGRect>, ShortcutHint)]`.
- `View.shortcutHint(_ hint: ShortcutHint)` modifier → attaches an `.anchorPreference`
  (bounds) under a stable id. Anchors are always collected (cheap); rendering is gated
  elsewhere, so when hints are off there is simply nothing drawn.

### 3. Overlay + badge view

- A single `.overlayPreferenceValue(ShortcutHintAnchorKey.self)` near the root in
  `ContentView`, wrapped in a `GeometryReader` to resolve anchors to rects.
- When `controller.isActive`, for each collected anchor it looks up the hint entry matching
  `controller.activeModifiers`; if present, renders a `HintBadge` positioned top-trailing on
  the element's rect, with an `.opacity` transition.
- `HintBadge`: translucent rounded capsule (`.regularMaterial`), monospaced key text +
  modifier SF Symbols, subtle shadow. Non-interactive (`allowsHitTesting(false)`).

This is the idiomatic SwiftUI approach for overlaying content positioned relative to
descendant views; it automatically tracks scrolling, window resizing, and tab switches
because anchors only exist for currently-visible annotated views.

## Annotated Elements

Each gets a `.shortcutHint(...)` carrying its combo→badge entries.

| Area | Elements | Badges |
|------|----------|--------|
| Workspace tab bar (`TerminalContainerView`) | Info, Coding Agent, dynamic tabs, New Terminal/Browser/Editor buttons | `⌘1`, `⌘2`, `⌘3–9`; `⌘T`/`⌘⇧T`, `⌘B`/`⌘⇧B`, `⌘O` |
| Workspace action buttons (`TerminalContainerView` / info area) | Start/Rerun, Focus Agent, split, archive | `⌘⇧⏎`, `⌘⏎`, `⌘⇧W` — only where the button is visible |
| Sidebar (`ProjectSidebar`) | selected project row, workstream rows, New | `⌘↑↓` (directional, on selected project), `⌘[ ]` (directional, on selected workstream), `⌘N` |
| Browser/editor (`BrowserView` / `EditorView`) | address bar, reload, save | `⌘L`, `⌘R`/`⌘⇧R`, `⌘S`/`⌘⇧S` — only when that view is active |

Directional cycle shortcuts (`⌘↑↓` projects, `⌘[ ]` workstreams) are not per-row actions;
they badge the currently-selected row to indicate the cycle direction keys.

## Settings

- New `@AppStorage("dockyard.showShortcutHints")` `Bool`, default **`true`**.
- A `Toggle` added to `SettingsView` in an appropriate existing section (General/Appearance),
  labelled "Show shortcut hints while holding ⌘" with a short help string.
- Both strings localized in all five locales (en, ca, de, es, sv).

## Testing

- **Unit (`./scripts/dev.sh test`):**
  - The flags reducer: ⌘ → active with `[.command]`; ⌘⇧ / ⌘⌥ → correct `activeModifiers`;
    no ⌘ → inactive; `enabled == false` → always inactive.
  - The combo→badge matching: given a `ShortcutHint` and an `activeModifiers`, returns the
    right badge or none.
- **Manual (`./scripts/dev.sh br`):** hold ⌘ across each annotated area; add ⇧/⌥ and confirm
  live swap; confirm terminal typing and all existing shortcuts still work; toggle the
  setting off and confirm badges never appear.

## Files Touched

- **New:** `Sources/Views/ShortcutHints.swift` (controller, reducer, `ShortcutHint`,
  preference key, `.shortcutHint` modifier, overlay, `HintBadge`).
- `Sources/DockyardApp.swift` — start the controller's monitors at launch; inject
  `environmentObject`.
- `Sources/Views/ContentView.swift` — root overlay.
- `Sources/Views/TerminalContainerView.swift` — tab bar + action button annotations.
- `Sources/Views/ProjectSidebar.swift` — project/workstream row + New annotations.
- `Sources/Views/BrowserView.swift`, `Sources/Views/EditorView.swift` — control annotations.
- `Sources/Views/SettingsView.swift` — toggle.
- `Localization/*/Localizable.strings` (×5) — toggle label + help.

## Risks / Open Questions

- **flagsChanged while terminal is first responder.** Local `NSEvent` monitors fire before
  dispatch, so modifier changes should be observed even with the Ghostty view focused. To be
  confirmed during implementation; if a local monitor proves insufficient, fall back to a
  global+local pair.
- **Anchor cost at scale.** Always-collected anchors are cheap, but if profiling shows
  overhead with many tabs/workstreams, annotations can be made conditional on the setting
  being enabled.
- **Default on vs off.** Shipped **on** for discoverability; trivially reversible via the
  toggle if it proves distracting.
