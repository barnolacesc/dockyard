# Workstream stage pills — design

Date: 2026-06-17
Branch: `dy/improve-merged-pr-visual`

## Problem

A workstream's place in its review lifecycle is the clearest "is this done?" signal, but
the sidebar barely shows it:

- **Merged is the quietest signal on the row.** When `prState == "MERGED"`, the row only
  prepends an 8pt purple `arrow.triangle.merge` glyph to the subtitle and tints the subtitle
  line purple (`ProjectSidebar.swift:1096-1112`). That competes — and loses — against the
  louder green active-port dot, the `±N` badge, and the agent-state orb. A merged workstream
  (usually = work done, safe to delete) looks almost identical to an active one.
- **"PR open / awaiting review" has no sidebar signal at all.** The review queue is invisible;
  there is nothing to scan for or group by.
- **The user has no say.** The look is derived purely from `gh` state. A merged PR that the
  user still intends to work on keeps the "merged" styling with no way to mark "I'm not done."

## Goals

1. Give a workstream's **lifecycle stage** its own loud, scannable channel in the sidebar:
   *Still working* (normal), *Needs review* (loud), *Done / merged* (recedes).
2. Let the user **override** the auto-derived stage per workstream via right-click, and return
   to *Auto* whenever — a layer *on top of* agent state, not a replacement for it.
3. Slot cleanly into PR #24's "one signal per channel" framework: never reuse a channel that
   already carries another meaning; leave the agent orb untouched.

## Non-goals

- Manual drag-to-reorder of workstreams (rows still auto-sort by `lastAccessedAt`). The loud
  *Needs review* styling lets the user find the review queue by eye; reordering is a possible
  later follow-up, explicitly out of scope here.
- Auto-archiving or auto-purging merged workstreams. *Done* recedes; it never acts on its own.
- Changing the Info tab's "Pull Request" section or the project-overview `PRBadge`. Those keep
  working; only the sidebar row gains the stage pill. (Their colors may be unified in a
  follow-up, but not here.)

## Dependency on PR #24

This builds **on top of** PR #24 (`dy/rework-sidebar-status-colors`, open), which introduces
`WorkstreamStatusStyle(agentState:isPathValid:)` as the single source of truth for the row's
visual decision and establishes the channel rules below. This work **extends** that helper; it
should land after #24 (rebase onto it, or merge #24 first). If #24's shape changes, re-fit the
extension — the conceptual channel split here does not depend on #24's exact field names.

### Channels already claimed by PR #24 (do not reuse)

| Channel | Meaning |
|---|---|
| Left orb **motion** (pulse) | agent **busy now** (`working`, green) |
| **Blue** (orb + label + row tint @0.10) | agent **needs input** (`waiting`) |
| **Accent** frame (left bar + fill) | **selected** row |
| Green static dot, title-adjacent | active **port** |
| Orange ⚠️ triangle + strikethrough | **broken path** |
| `±N` in `.secondary` | uncommitted-changes metadata |

The stage signal therefore takes an **unused spatial channel — a pill on the trailing (right)
edge of the row** — in the **purple "PR family" hue** (purple is already the merged color, so
"PR lifecycle = purple" stays consistent and never collides with the agent orb's green/blue).

## The model

A single per-workstream **stage** the user can set, defaulting to **Auto**:

```swift
enum WorkstreamStage: String, Codable, CaseIterable {
    case auto      // follow the PR (default)
    case working   // "Still working" — force the normal look
    case review    // "Needs review" — force the loud look
    case done      // "Done / merged" — force the recede look
}
```

The renderer resolves the **display stage** from `(stage, prState)`:

```swift
enum WorkstreamDisplayStage { case normal, review, done }

func displayStage(stage: WorkstreamStage, prState: String?) -> WorkstreamDisplayStage {
    switch stage {
    case .working: return .normal
    case .review:  return .review
    case .done:    return .done
    case .auto:
        if prState == "MERGED" { return .done }
        if prState == "OPEN"   { return .review }
        return .normal
    }
}
```

`isManuallySet = (stage != .auto)` drives a small "manual" mark so Auto and overridden rows are
distinguishable.

## Visual design

Pill lives at the row's trailing edge, before the `Spacer()`. On hover the existing remove `✕`
still appears at the far right; the pill dims slightly on hover so the two don't fight.

```
STILL WORKING  (display: .normal — today's look, NO pill)
 ●  Fix the login timeout bug
    dy/fix-login-timeout

NEEDS REVIEW  (display: .review — loud, FILLED pill, full-strength row)
 ●  Fix .dockyard.json json schema            ┃ ◍ Review #24 ┃
    dy/fix-dockyard-de  ±1

DONE / MERGED  (display: .done — row RECEDES, quiet OUTLINE pill)
 ○  Fix .dockyard.json json schema  (dimmed)    ✓ Merged #24
    dy/fix-dockyard-de

MANUAL OVERRIDE  (PR merged, user set "Still working")
 ●  Fix .dockyard.json json schema            ⌁ Working
    dy/fix-dockyard-de
```

**`.review` (loud):**
- Filled capsule: `Color.purple` fill, `.white` foreground.
- Icon `arrow.triangle.pull` + label `Review` + `#<number>` when a PR number is known
  (label only when stage is forced manually with no PR).
- Row itself stays full strength (label `.primary`).

**`.done` (recede):**
- Outline capsule: clear fill, `Color.purple` stroke @ ~0.5, purple foreground @ ~0.7.
- Icon `checkmark` (or `arrow.triangle.merge`) + label `Merged` (Auto/merged) or `Done`
  (manual) + `#<number>` when known.
- Row recedes: headline → `.secondary`, whole row opacity ~0.65. **No strikethrough** (that
  channel belongs to broken paths).

**Manual mark:** when `isManuallySet`, prepend a small `pin.fill` (~7pt, matching the pill
foreground) inside the pill. For a manual `.working` (which has no pill of its own) show a
minimal bare pill `⌁ Working` so the override is visible; clearing back to Auto removes it.

**Precedence with selection / agent state:** unchanged. The accent selection frame and the
left agent orb render exactly as PR #24 defines; the stage pill is an independent trailing
element. A row can be selected *and* needs-review *and* have a working orb simultaneously.

## Data model

Add to `Workstream` (`Sources/Models/Project.swift`):

```swift
var stage: WorkstreamStage = .auto
```

**Backward-compatible decoding is mandatory.** `Workstream` is `Codable` and persisted in
UserDefaults (`dockyard.projects`); Swift's *synthesized* `Decodable` does **not** apply
property defaults for missing keys, so adding a bare field would make every existing stored
workstream throw on decode and risk wiping the user's projects. Add an explicit decoder that
defaults the field:

```swift
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    worktreePath = try c.decodeIfPresent(String.self, forKey: .worktreePath)
    bypassPermissions = try c.decode(Bool.self, forKey: .bypassPermissions)
    lastAccessedAt = try c.decode(Date.self, forKey: .lastAccessedAt)
    stage = try c.decodeIfPresent(WorkstreamStage.self, forKey: .stage) ?? .auto
}
```

(Keep the existing memberwise `init`; add `stage: WorkstreamStage = .auto` to its signature.
`WorkstreamStage` decodes from a string, so unknown future values should also fall back to
`.auto` — decode via `decodeIfPresent` of the raw string and map, treating unknown as `.auto`.)

## Interaction — right-click menu

Add a `Status` submenu to `WorkstreamRow`'s `contextMenu` (`ProjectSidebar.swift:1126-1175`),
placed just above the existing `Rename` group:

```
Status ▸   ✓ Auto  (follows the PR)
           Still working
           Needs review
           Done / merged
```

- The current stage shows a checkmark; selecting a value sets it (selecting `Auto` clears the
  override). Use a `Picker` or `Button`s with `Label`/checkmark.
- `WorkstreamRow` gains `var stage: WorkstreamStage` and `var onSetStage: (WorkstreamStage) -> Void`.
- The parent writes `projects[pi].workstreams[wi].stage = newValue` and calls the existing
  persistence path (`onProjectsChanged()` / the same flow used by rename), then lets the row
  re-render. No new store is needed.

## Components & files

1. **`WorkstreamStage` enum (new)** — in `Sources/Models/Project.swift` next to `Workstream`,
   plus the `stage` field and custom `init(from:)`.
2. **`Workstream` display-stage resolver** — a pure `func displayStage(prState:) ->
   WorkstreamDisplayStage` (and `isManuallySet`) on `Workstream`, or a free function near
   `WorkstreamStatusStyle`. Pure and unit-tested.
3. **`WorkstreamStatusStyle` (extend, from PR #24, `ProjectSidebar.swift`)** — accept the
   resolved display stage + `isManuallySet` and expose the pill decision (fill vs outline,
   color, icon, label) and the row-recede flag (`.done` → label `.secondary`, opacity ~0.65).
   Keeps the single-source-of-truth pattern; agent-orb fields unchanged.
4. **`StagePill` view (new, small)** — renders the trailing capsule from the style. Filled vs
   outline, icon + label + optional `#number` + optional manual mark.
5. **`WorkstreamRow` (`ProjectSidebar.swift:1077`)** — add `stage`, `prNumber` (already passed),
   `onSetStage`; place `StagePill` before `Spacer()`; apply the recede on `.done`; add the
   `Status` submenu. Remove the old inline merged-glyph/purple-subtitle block (replaced).
6. **Row instantiation (`ProjectSidebar.swift:184-203`)** — pass `stage: workstream.stage` and
   `onSetStage:` that mutates the workstream and persists.

## Testing

- `WorkstreamStage` resolution (pure): `.auto` + `MERGED` → `.done`; `.auto` + `OPEN` →
  `.review`; `.auto` + nil → `.normal`; each manual value maps to its fixed display stage
  regardless of `prState`; `isManuallySet` true iff `stage != .auto`.
- `Workstream` Codable backward-compat: decoding JSON **without** a `stage` key yields `.auto`
  (guards the UserDefaults migration); decoding an unknown `stage` string yields `.auto`;
  round-trip encode/decode preserves an explicit stage.
- `WorkstreamStatusStyle` (extend PR #24's tests): `.review` → filled purple pill, full-strength
  row; `.done` → outline pill + recede flag; `.normal` → no pill; manual flag surfaces the mark.

## Localization

New user-facing strings — add to all 5 locales (en, ca, de, es, sv):
`Status`, `Auto`, `Still working`, `Needs review`, `Done / merged`, `Review`, `Merged`, `Done`,
and a help/tooltip for the pill. Pill `#<number>` is interpolated, not localized.

## Out of scope / follow-ups

- Unifying the Info-tab "Pull Request" section and the project-overview `PRBadge` with the same
  pill language.
- Manual drag-reorder and/or auto-grouping the review queue together.
- A one-click "Archive" affordance on `.done` rows (the recede look already invites cleanup;
  Purge already exists in the menu and Info tab).
