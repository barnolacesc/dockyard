# Sidebar Manual Reorder — Design

**Date:** 2026-06-17
**Status:** Approved (brainstorm), pending implementation plan

## Summary

Let the user drag projects up and down to reorder the sidebar tree — each project
carries its workstreams with it — and drag workstreams up and down within their own
project. The arranged order is stable and persisted across relaunches.

Today the sidebar has no manual ordering at all: both projects and workstreams are
displayed strictly in most-recently-used (`lastAccessedAt`) order, recomputed on every
terminal activity. This design replaces that automatic recency sort, in the navigation
surfaces, with a user-controlled manual order. The pinned "Recent" section, "Open PRs"
section, and the Project Overview grid's own sort toggle are unaffected and continue to
use recency.

## Current Behavior (as investigated)

- **Models** (`Sources/Models/Project.swift`): `Project` and `Workstream` have no
  position/order field. Display order is derived at render time.
- **Sidebar tree** (`ProjectSidebar.swift:74-91`): `recomputeSortedIDs()` and
  `rebuildIndices()` sort projects and workstreams by `lastAccessedAt` descending.
  `handleTerminalActivity()` (`:135`) bumps `lastAccessedAt` and re-sorts the cached IDs
  on every terminal activity. The persisted array order in UserDefaults
  (`dockyard.projects`) is ignored for display.
- **Existing sidebar drag-and-drop is add-only**: `.onDrop(of: [.fileURL])`
  (`ProjectSidebar.swift:639`) imports a directory dropped from Finder as a new project.
  There is no `.onMove` / reorder gesture today.
- **Collapsed rail** (`SidebarRail.swift:26-31`): `sidebarRailSortedProjects` /
  `sidebarRailSortedWorkstreams` also sort by `lastAccessedAt`, then number projects 1…N
  and letter workstreams a, b, c… in that order.
- **Keyboard cycling** (`ContentView.swift`): `cycledWorkstreamID` (`:51`),
  `cycleGlobalWorkstream` (`:681,687`), and `cycleProject` (`:715`) all sort by
  `lastAccessedAt`. The comment on `cycleProject` already states its intent is to "cycle
  through projects in sidebar display order."
- **Separate recency aggregations**: the pinned "Recent" section
  (`ProjectSidebar.swift:297`) and "Open PRs" section are independent recency lists.
  `ProjectSortOrder` (recent / alphabetical) exists but is only used by the Project
  Overview grid (`ProjectOverviewView.swift`), never by the sidebar.

## Goals

- Drag a project vertically to any position among the other projects; its workstreams
  move with it.
- Drag a workstream vertically to any position **within its own project**.
- The manual order is stable — it never auto-resorts by recency — and persists across
  relaunches.
- Navigation surfaces stay consistent with the visible tree order: the collapsed rail's
  number/letter assignment and keyboard cycling follow the same manual order.

## Non-Goals

- **No cross-project workstream moves.** A workstream is a git worktree bound to one
  specific repository; dropping it under a different project is blocked.
- **No Recent/Manual mode toggle.** Manual order simply replaces recency in the tree;
  there is no per-user switch.
- **No Project Overview grid changes.** Its existing Recent/A-Z toggle is untouched; a
  "Manual" option there can be a follow-up.
- **No new model fields and no Codable schema change.**

## Source of Truth — Array Order

The array order of `ProjectList.items` and of each `project.workstreams` **becomes** the
canonical manual order. Both already persist to UserDefaults (`dockyard.projects`) via
`ProjectStore.save`. The change is to **stop overriding array order with a recency sort at
display time** and to make reorder gestures mutate those arrays.

`Project` and `Workstream` are untouched — no `order:` field, no reindexing, no Codable
migration. Array index *is* the order.

## Display Order — Drop Recency Sort From Navigation Surfaces

| Location | Today | Change |
|----------|-------|--------|
| `ProjectSidebar.recomputeSortedIDs()` (`:74`) | `projects.sorted { lastAccessedAt > }` | `projects.map(\.id)` (array order) |
| `ProjectSidebar.rebuildIndices()` (`:86`) | workstream IDs sorted by `lastAccessedAt` | `project.workstreams.map(\.id)` (array order) |
| `ProjectSidebar.handleTerminalActivity()` (`:135`) | bumps `lastAccessedAt` **and** re-sorts cached IDs | still bumps `lastAccessedAt` (for Recent + seed); **no longer re-sorts** the tree |
| `sidebarRailSortedProjects` (`SidebarRail.swift:26`) | sort by `lastAccessedAt` | return `projects` in array order |
| `sidebarRailSortedWorkstreams` (`SidebarRail.swift:30`) | sort by `lastAccessedAt` | return `workstreams` in array order |
| `cycledWorkstreamID` (`ContentView.swift:51`) | sort by `lastAccessedAt` (usable paths) | array order (keep usable-path filter) |
| `cycleGlobalWorkstream` (`ContentView.swift:681,687`) | sort projects + workstreams by `lastAccessedAt` | array order (keep usable-path filter) |
| `cycleProject` (`ContentView.swift:715`) | sort by `lastAccessedAt` | array order |

`lastAccessedAt` is **still maintained** on terminal activity, because it continues to
drive the pinned "Recent" section and the one-time seed (below).

**Unchanged (intentionally still recency-based):** the pinned "Recent" section, "Open PRs",
the Project Overview grid's Recent/A-Z toggle, and `ContentView.initialSelection()` (the
most-recently-used project is still a reasonable launch selection).

## Drag Interaction — Native `.onMove`, Nested ForEach

Refactor `ProjectSidebar.projectRows()` from one flat, interleaved `ForEach` (project
header rows and workstream rows as siblings, indented with `.padding(.leading, 28)`) into a
proper two-level structure inside the existing `List(selection:)`:

- An **outer** `ForEach` over project IDs (in array order) with `.onMove` that reorders the
  `projects` array.
- An **inner** `ForEach` (rendered only for an expanded project) over that project's
  workstream IDs with `.onMove` that reorders only `projects[i].workstreams`.

macOS `List` provides native drag-to-reorder for `.onMove` rows. The within-level
constraint is **structural and free**: the outer `.onMove` can only reorder projects, the
inner `.onMove` only reorders workstreams within their owning project. Cross-project drops
are impossible because each project's workstreams live in their own `ForEach`.

Preserved as-is: `List(selection:)` click-selection, the `ScrollViewReader` /
`deferSelectionExpansion` scroll-to behavior, the `.tag(SidebarSelection.…)` tags, the
cached index dictionaries (`cachedProjectIndex`, `cachedWorkstreamIndex`), and the existing
`.onDrop(of: [.fileURL])` Finder-folder import. `.onMove` (reorder, internal) and the
file-URL drop (add, external) operate on different payloads and do not collide.

### `.onMove` handlers

- **Project move:** `projects.move(fromOffsets:toOffset:)` on the live `projects` binding,
  then `onProjectsChanged()` and refresh the cached index dictionaries.
- **Workstream move:** `projects[pIdx].workstreams.move(fromOffsets:toOffset:)` for the
  owning project, then `onProjectsChanged()` and refresh caches.

Both should be small, pure-ish helpers that operate on `inout [Project]` so they can be
unit-tested without the view.

### Component boundaries

- The existing `ProjectHeaderRow` and `WorkstreamRow` subviews are reused unchanged as the
  draggable rows.
- The reorder logic is two free functions (`moveProjects`, `moveWorkstreams(in:)`) taking
  plain inputs (`inout [Project]`, offsets) — understandable and testable in isolation.

### Technical risk

The main unknown is `.onMove` behavior on a `List(selection:)` that mixes an outer project
`ForEach` with nested per-project workstream `ForEach`es, while a separate `.onDrop` for
file URLs is attached to the same List. Validate early that:
1. dragging a project row reorders projects and the expanded children render under the
   moved project;
2. dragging a workstream row reorders only within its project;
3. click-selection and the Finder-folder drop still work.

If native `.onMove` fights the nested structure, the fallback is custom
`.draggable`/`.dropDestination` with typed payloads (kind + id + owning project) and a
hand-built drop indicator — more code, kept in reserve.

## New-Item Placement — Top

With a stable manual order, newly created items insert at the top of their list so the
user immediately sees what they just created (it is also auto-selected):

- **New project:** `ContentView.swift:497` `projects.append(project)` → `projects.insert(project, at: 0)`.
- **New workstream:** `ContentView.swift:462` `projects[index].workstreams.append(workstream)` → `projects[index].workstreams.insert(workstream, at: 0)`.

(Today these are `append`; display position was masked by the recency sort, so this is the
first time array position is user-visible.)

## Migration / Seed — One-Time

On the first launch after this ships, the existing arrays are in insertion order, but the
tree has always shown recency order — so seed the manual order from today's recency order
to avoid a visible reshuffle:

1. Sort `ProjectList.items` by `lastAccessedAt` descending.
2. Within each project, sort `workstreams` by `lastAccessedAt` descending.
3. `ProjectStore.save(...)` the reordered arrays.
4. Guard with a one-time flag `dockyard.sidebarManualOrderSeeded` (Bool in UserDefaults),
   following the `Sources/Models/CacheMigration.swift` pattern.

After seeding, array order is canonical and is never auto-resorted again. Thereafter
`lastAccessedAt` only feeds the Recent section.

## Persistence

Reorder gestures and new-item insertion mutate the `projects` binding, which flows through
the existing `onProjectsChanged()` → debounced `ProjectStore.save` path in `ContentView`
(`:273`). No new persistence code is required.

## Localization & Accessibility

- Native `.onMove` provides standard drag affordances and VoiceOver reorder support for
  free.
- No new user-facing strings are anticipated. If any reorder hint/tooltip or accessibility
  label is added, it follows the project rule and is added to all 5 locales (en, ca, de,
  es, sv).

## Keyboard Shortcuts

None added or changed. Cmd+↑/↓ (projects) and Cmd+[ /] (workstreams) keep their bindings;
only the order they traverse changes (recency → manual), which is covered above.

## Testing

**Unit (pure functions):**
- `moveProjects`: moving project at index 0 to the end produces the expected array; a
  workstream-bearing project carries its `workstreams` with it.
- `moveWorkstreams(in:)`: reordering within a project changes only that project's
  `workstreams`; other projects untouched.
- Seed migration: given an unsorted array with known `lastAccessedAt` values, produces
  recency-descending array order for projects and per-project workstreams, and sets the
  seeded flag; running twice is a no-op the second time.
- Order parity: rail (`sidebarRailSortedProjects/Workstreams`) and cycling
  (`cycledWorkstreamID`, `cycleProject`) return array order, not recency order.

**Manual QA:**
- Drag a project to the bottom while it is expanded — its workstreams move with it.
- Reorder workstreams within a project; confirm they cannot be dropped under another
  project.
- Relaunch — order persists.
- Create a new project and a new workstream — each appears at the top and is selected.
- Confirm Cmd+number / letter rail selection matches the expanded tree, and Cmd+↑/↓ and
  Cmd+[ /] cycle in the visible order.
- Confirm the Finder-folder drop (add project) and the "Recent" / "Open PRs" sections are
  unchanged.

## Open Questions

None blocking. The `.onMove`-on-nested-ForEach interaction (Technical risk, above) is the
item to validate first during implementation.
