# Sidebar status colors & orbs — design

Date: 2026-06-17
Branch: `dy/rework-sidebar-status-colors`

## Problem

The sidebar overloads a single visual language, so distinct meanings collapse together:

- The macOS **system accent** (orange for this user) is reused for needs-input label text
  (`ProjectSidebar.swift:1086`), the needs-input row tint (`:208`), the needs-input orb
  (`:1193`), the `±N` dirty badge (`:1107`), and the path-error icon (`:1189`). "Needs input,"
  "has uncommitted changes," and "broken path" therefore all read as the same orange.
- The **orb and the color say the same thing twice**: a needs-input row gets both a pulsing
  orb *and* accent text. The glow is decorative rather than informative.
- The **selected** workstream uses only the system grey selection, so it is the *least*
  prominent row despite being the focused one.
- **Agent state never expires.** `AgentStateStore.loadValidated` (`AgentStateStore.swift:92`)
  trusts the last hook a workstream emitted as long as its PID is alive. An agent that finished
  its turn keeps a `working`/`waiting` orb indefinitely — one live state file has been stuck on
  `waiting` since 2026-05-17. This is why "jarvis" shows a moving orb while feeling idle.
- Project repo paths and the Recent rows are small/dim and hard to read.

## Goals

1. Give each piece of information its own visual channel; never signal one meaning twice.
2. Make "needs my input" and "this is the selected row" each unmistakable and mutually distinct.
3. Make the working orb *trustworthy* by expiring stale states.
4. Improve legibility of project repo paths and Recent rows.

## Non-goals

- A real activity heartbeat (periodic writes while working). Costs ~0 tokens but adds per-workstream
  hook wiring and helper changes; deferred. We use a time-based freshness cap instead.
- Reworking hook reliability / the `dy-agent-state` helper.
- Any change to workspace/tab views; this is sidebar-only.

## The channel model

Each workstream row answers three independent questions. Each gets one channel, and no channel
is reused for a second meaning:

| Question | Channel |
|---|---|
| Is the agent **busy right now**? | **Motion** — a pulsing orb (only `working` pulses) |
| Does this row **need me**? | **Color** — blue on the orb *and* the label |
| Is this the row **I'm focused on**? | **Frame** — accent left bar + faint accent fill |

`working` carries its meaning through motion, so its label stays neutral. `needs-input` is
static (the agent genuinely isn't doing anything) but boldly colored. Selection is orthogonal
to both, so a selected row that also needs input shows the accent frame *and* the blue orb/label.

## State → visual mapping

| State | Orb | Label | Subtitle | Row background |
|---|---|---|---|---|
| `working` | green, **pulsing** | primary | tertiary | — |
| `waiting` (needs input) | blue, **static** | **blue** | blue @ 0.8 | blue @ 0.10 |
| `idle` | small grey, static | primary | tertiary | — |
| no agent / `nil` | none | primary | tertiary | — |
| broken path | orange ⚠️ triangle | secondary + strikethrough | tertiary | — |
| **selected** (overrides row bg only) | keeps state orb | keeps state color | keeps state color | **accent left bar (3pt) + accent @ 0.10 fill** |

Colors are **fixed/semantic** (`Color.green`, `Color.blue`, `.tertiary`) and adapt to light/dark.
The **system accent is used only for selection.** Precedence for the row background: selected
> needs-input > clear.

### Secondary signals (de-conflicted from accent)

- `±N` dirty badge: `.orange` → **`.secondary`** (it's metadata, not a state).
- Active-port dot (next to the title): keep `.green`; its title-adjacent position and static
  fill distinguish it from the left-edge pulsing working orb.
- Merged PR arrow: `.purple` (unchanged).
- Broken-path triangle: orange (unchanged) — a distinct glyph + strikethrough already separates
  it from the accent.

## Staleness fix

Add a time-based freshness cap so a stale snapshot decays to `idle`:

- `working` older than **30 min** → treated as `idle`.
- `waiting` older than **2 h** → treated as `idle`.
- `idle`, dead PID, or unparseable → unchanged (dead PID still returns `nil`/no dot).

Rationale for the asymmetry: aggressively expiring `waiting` would *hide a real "needs input"
row* just because time passed — the worst failure, since that's the signal we most want to keep.
A slightly stale static blue is harmless; a long-running real `working` turn up to 30 min keeps
its glow.

**Re-evaluation:** stale files emit no FSEvents, so decay never fires on file changes alone.
`AgentStateStore` gains a lightweight periodic re-scan (~60 s timer calling `refreshState()`),
so an aging snapshot is recomputed and the orb goes quiet on its own.

## Fonts

- Project repo path (`ProjectHeaderRow`, `ProjectSidebar.swift:975`): 10 → **12pt**.
- Recent row name (`RecentRow:1297`): 11 → **12pt**; project name (`:1300`): 9 → **11pt**;
  clock icon (`:1294`): 9 → **11pt**.

## Components & files

1. **`WorkstreamStatusStyle` (new, pure helper)** — maps `(AgentState?, isPathValid: Bool)` to
   its visual decision: orb color, `pulses: Bool`, label color, subtitle color, optional row
   tint. Single source of truth for the mapping; unit-testable in isolation. Likely a small
   struct/function near `ActivityIndicator` in `ProjectSidebar.swift`.
2. **`ActivityIndicator` (`ProjectSidebar.swift:1179`)** — consume `WorkstreamStatusStyle`:
   pulse only when `pulses`, fill from the style. Drops the per-state `if/else` color logic.
3. **`WorkstreamRow.body` (`:1077`)** — label/subtitle colors from the style; `±N` → `.secondary`.
4. **`listRowBackground` (`:206`)** — selected → accent left bar + accent @ 0.10 fill;
   else needs-input → blue @ 0.10; else clear.
5. **`AgentStateStore` (`AgentStateStore.swift`)** — add pure `decayedState(_ snapshot:, now:)`
   applied in `scanDirectory`; add ~60 s periodic re-scan timer.
6. **`ProjectHeaderRow` (`:974`)** and **`RecentRow` (`:1286`)** — font bumps.

## Testing

- `WorkstreamStatusStyleTests` — assert orb color / `pulses` / label color for each of:
  `working`, `waiting`, `idle`, `nil`, invalid-path.
- `AgentStateStore` decay tests (extend `AgentStateTests.swift`):
  - `working` with `updatedAt` 31 min ago → `idle`.
  - `working` 5 min ago → `working`.
  - `waiting` 31 min ago → `waiting` (not yet decayed).
  - `waiting` 3 h ago → `idle`.
  - dead PID → `nil` (existing behavior preserved).

## Localization

No new user-facing strings (color/font changes only). Existing "Uncommitted changes" help is kept.

## Out of scope / follow-ups

- Activity heartbeat for exact working accuracy (see Non-goals).
- Investigating whether missed `Stop`/`UserPromptSubmit` hooks are the deeper cause of stuck
  states (relates to the prior background-setup refactor regression).
