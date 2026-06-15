# Collapsible Sidebar Rail — Design

**Date:** 2026-06-16
**Status:** Approved (brainstorm), pending implementation plan

## Summary

Add a compact, VS-Code-style icon rail as a third sidebar state. Today the sidebar is
either the full-width pane or fully hidden. This adds an intermediate **collapsed** state:
a ~60pt rail showing projects as numbers, the selected project's workstreams as letters,
a compact usage meter, and the existing Update / `+` / gear buttons — dropping the creator
credit and Recent section.

## Goals

- A third sidebar mode that is narrow (single "icon" column) like an editor activity bar.
- Keep all navigation working: selecting projects/workstreams drives the detail pane
  exactly as the full sidebar does.
- Preserve the at-a-glance status signals (waiting agents, dirty files) and usage meter.
- Two independent, conventional controls for switching states.

## Non-Goals

- No change to the full (expanded) sidebar's content or behavior.
- No redesign of the detail pane, workspace, or any view other than the sidebar.
- No new data sources — the rail is a presentation layer over existing state.

## The Three States

A new setting `dockyard.sidebarMode` (`@AppStorage`, enum-backed string) with three values:

| Mode | What you see | Width |
|------|--------------|-------|
| `expanded` | Today's full sidebar, unchanged | Draggable 160–350pt (as now) |
| `collapsed` | The new icon rail | Fixed ~60pt |
| `hidden` | Nothing; detail fills the window | 0 |

Default is `expanded`. The mode persists across relaunches.

`hidden` is a separate axis from `expanded`/`collapsed`: hiding then showing returns the
sidebar to whichever **visible** mode (`expanded` or `collapsed`) was last active.

## Interaction Model — Two Independent Controls

Rejected the single 3-way cycle (Expanded → Collapsed → Hidden → repeat) because "hidden"
is conceptually a different axis from "how wide when visible," and a cycle forces you
through the rail to get from full to hidden.

- **Collapse ⟷ Expand** — a chevron button at the top of the sidebar (where the
  sidebar-toggle icon sits today) toggles between rail and full. New keyboard shortcut
  **Cmd+Option+.**
- **Hide ⟷ Show** — unchanged: **Cmd+Option+S** / the macOS sidebar toggle. On show,
  restores the last visible mode.

## The Collapsed Rail

A new `SidebarRail` view (own file in `Sources/Views/`), laid out top → bottom:

### Projects and workstreams
- **Project tiles** — numbers `1…N` in current sidebar sort order.
- The **selected** project gets a ring and **expands inline** to show its workstreams as
  letter tiles `a, b, c…` (in the same order the full sidebar uses). The **active**
  workstream tile is accent-highlighted (orange).
- **All other projects stay collapsed** to just their number — workstream letters are only
  shown for the selected project.
- Clicking a project tile selects that project (and expands it). Clicking a letter tile
  selects that workstream. Selection uses the same `SidebarSelection` binding as the full
  sidebar, so the detail pane reacts identically.

### Status bubbling
- A **collapsed** project tile shows an **orange dot** when any workstream inside is
  waiting on the user, plus a small **dirty-file count** when any workstream is dirty.
- The **selected/expanded** project shows those signals on its individual letter tiles
  instead (orange dot + dirty badge per workstream), not on the project number.

### Hover
- Hovering any tile shows a tooltip with the real name: project directory name for a
  number tile, `dy/<branch>` for a letter tile.

### Usage
- Both usage bars, compact: `56%` orange (Current 5-hour) + `67%` green (Weekly 7-day),
  each with its thin progress bar. Reuses `ClaudeUsageStore` and the existing percentage
  logic from `SidebarStatusStrip`.

### Bottom buttons
- **Update** button with its commits-ahead count badge (existing `AppUpdater` behavior).
- **`+`** button (same add-project / add-workstream menu as the full sidebar).
- **gear** (settings).
- **Dropped in collapsed mode:** the creator credit line, the Recent section, the
  folder/stack/PR counts line, and the help (`?`) button.

## Architecture

- `ProjectSidebar` reads `sidebarMode`. When `collapsed`, it renders the new `SidebarRail`
  instead of its current body; when `expanded`, it renders the body unchanged.
- Column width is derived from the mode and applied via `navigationSplitViewColumnWidth`:
  - `expanded` → `min: 160, ideal: 200, max: 350` (unchanged)
  - `collapsed` → fixed ~60pt (min == ideal == max)
  - `hidden` → continues to use the existing `columnVisibility` / `toggleSidebar` path
- `SidebarRail` lives in its own file and is fed the same `projects` / `selection`
  bindings and the same environment objects the full sidebar already consumes
  (`AppEnvironment`, `AgentStateStore`, `WorkstreamActivityTracker`, `ClaudeUsageStore`).
  No new data plumbing.
- The rail reuses existing logic for dirty state, waiting-agent detection, usage
  percentages, and the Update button — it is presentation only.

### Components / boundaries
- `SidebarRail` — the rail container; owns layout and the project/workstream tiles.
- `RailProjectTile` / `RailWorkstreamTile` (private subviews) — one tile each, responsible
  for rendering a number/letter, selection ring/highlight, status dot/badge, and hover
  tooltip. Each takes plain inputs (label, selected flag, status) and emits selection via
  the shared binding — understandable and testable without the rest of the rail.
- A compact usage view, either a slimmed reuse of `SidebarStatusStrip`'s rows or a small
  shared subview, to avoid duplicating the percentage/estimate logic.

### Technical risk
Getting `NavigationSplitView` to honor a fixed ~60pt sidebar column cleanly (the value is
below today's `min: 160`) is the main unknown. Validate this early. If `NavigationSplitView`
fights the fixed narrow width, fall back to rendering a custom split for the sidebar column.

## State & Persistence

- `dockyard.sidebarMode` in `@AppStorage` (default `expanded`).
- The expanded sidebar's drag width continues to be managed by `NavigationSplitView` as
  today; collapsing does not destroy it — expanding returns to the prior draggable width.

## Localization & Accessibility

- New user-facing strings (tooltips, accessibility labels such as "Expand sidebar",
  "Collapse sidebar", project/branch names, "Update") follow the project rules and are
  added to all 5 locales (en, ca, de, es, sv).
- Tiles expose accessibility labels with the real names even though they display
  numbers/letters.

## Keyboard Shortcuts

New: **Cmd+Option+.** toggles collapse/expand. Per project convention, update:
`DockyardApp.swift` (menu command), `HelpView.swift`, `README.md`, and the website
shortcuts section. (Cmd+Option+S hide/show is unchanged.)

## Testing

- Unit-test the project→number and workstream→letter mapping and the status-bubbling rule
  (collapsed project reflects any inner waiting/dirty workstream; expanded project shows
  per-workstream instead).
- Verify mode persistence round-trips through `@AppStorage`.
- Manual: collapse/expand/hide transitions, selection parity with the full sidebar, and
  the fixed-width column behavior.

## Open Questions

None blocking. The `NavigationSplitView` fixed-width behavior is the item to validate first
during implementation.
