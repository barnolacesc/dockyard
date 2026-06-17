# Preserve the Active Workspace Tab on Switch — Design

**Date:** 2026-06-17
**Status:** Approved (brainstorm), pending implementation plan

## Summary

Switching between workstreams currently always lands you on the **Coding Agent** tab,
regardless of which tab (Info, a Browser, a Terminal, an Editor) you were on before. This
is a regression caused by an auto-focus side-effect, not a missing feature — the per-workstream
tab-restoration machinery already exists and works within a session; it is simply being
overridden on every selection.

This design has two parts:

1. **Fix the override** so selecting a workstream restores its exact last tab (the reported bug).
2. **Persist the full tab layout to disk** so the exact tab — including Terminal, Browser, and
   Editor tabs — is also restored after a full app quit and relaunch.

## Goals

- Selecting a workstream restores the exact tab you last had open there (Info / Agent /
  Terminal / Browser / Editor), both when switching during a session and after an app restart.
- Keep the existing explicit "jump to Coding Agent" action (Cmd+Return / menu) working.
- No regression to keyboard focus for the common case: if the restored tab is the Agent or a
  Terminal, the keyboard is ready there.

## Non-Goals

- No change to which tabs are *available* or how they're created.
- No restoration of terminal scrollback — terminals re-create as fresh shells.
- No capture/restore of an arbitrary navigated browser URL — restored browser tabs open at the
  default (port) URL. (Confirmed with user.)
- No keyboard-focus changes beyond what falls out naturally (we do not add a "pull focus into
  the active surface" behavior).

## Root Cause

`ContentView.swift` `onChange(of: selection)` posts `.focusAgent` whenever the new selection is
a workstream:

```swift
// Auto-focus terminal when selecting a workstream
if case .workstream = newValue {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .focusAgent, object: nil)
    }
}
```

The workspace's handler (`TerminalContainerView.swift`) responds:

```swift
.onReceive(NotificationCenter.default.publisher(for: .focusAgent)) { _ in
    guard isActive else { return }
    activeTab = .agent
}
```

On every switch the sequence is: restore the real last tab (in `init` and `.onAppear`) → then
the `DispatchQueue.main.async` `.focusAgent` runs *after* the restore → `activeTab = .agent`
wins. The async dispatch is what makes it deterministic: it always clobbers the restored tab.
That is the exact "no matter where I was, it goes to the Agent" symptom.

The same `.focusAgent` notification is also posted by the **Cmd+Return / "Coding Agent" menu
item** (`DockyardApp.swift`). That use is intentional and must stay.

## Current Restoration Machinery (for reference)

Two stores exist today:

| Store | Where | Fidelity | Lifetime |
|-------|-------|----------|----------|
| `TerminalSurfaceCache.tabSnapshots` | in-memory (`@StateObject` cache, app lifetime) | Full `WorkspaceTabSnapshot` (all tab types, active tab, counts, titles, editor paths) | Until app quit |
| `WorkspaceStateStore` (`dockyard.workspaceTabs`) | UserDefaults | Lossy: `RestorableWorkspaceTab` collapses Terminal/Browser/Editor → Info; keeps only Info vs Agent | Across restarts |

- Snapshot is saved on `.onDisappear` (guarded by `workspaceStarted`), on `.onChange(of: isActive)`
  becoming inactive, and on tab add/close via the private `saveTabSnapshot()`.
- `WorkspaceStateStore` is written on every `.onChange(of: activeTab)`.
- On entry, `startupWorkspaceTabState(snapshot:savedTab:)` builds the initial state: it prefers
  the in-memory snapshot; otherwise falls back to the lossy `savedTab`.
- `restoreTabSnapshot` runs `WorkspaceTabSnapshot.reconciled(liveSurfaceIDs:)`, which drops dead
  terminal tabs and, if the active tab was one of them, falls back to `.agent`.

Within a session the in-memory snapshot is full-fidelity, so **Part 1 alone fixes the reported
bug**. Across a restart the in-memory snapshot is gone and only the lossy store remains, so
**Part 2** is needed to restore Terminal/Browser/Editor tabs after relaunch.

Tab identities are deterministic: terminal/browser/editor tab UUIDs are
`derivedUUID(from: workstreamID, salt: "terminal-\(count)")` etc. This means a persisted tab
list reproduces the same surface IDs on relaunch — surfaces re-create lazily with matching IDs.

## Part 1 — Stop forcing the Agent tab on selection

- Remove the `if case .workstream = newValue { … post(.focusAgent) }` block from
  `ContentView.swift` `onChange(of: selection)`.
- Leave the `.focusAgent` poster in `DockyardApp.swift` (Cmd+Return / "Coding Agent") untouched.
- Leave the `.onReceive(.focusAgent)` handler in `TerminalContainerView` untouched — it remains
  the implementation of the explicit action.

Result: the existing restore in `init` / `.onAppear` is no longer overridden. For Agent and
Terminal tabs, keyboard focus still lands in the surface because `TerminalView.viewDidMoveToWindow`
claims first responder when the surface becomes visible. For Info/Browser tabs there is nothing
to type into, so no focus change is needed.

## Part 2 — Persist the full tab layout across restarts

### Make the snapshot Codable

- Add `Codable` conformance to `WorkspaceTab` (enum with associated `UUID`s — Swift can
  synthesize) and `WorkspaceTabSnapshot`.

### Persistent full-fidelity store

- Introduce a persistent store for the full `WorkspaceTabSnapshot`, keyed by workstream UUID, in
  UserDefaults under a **new** key (e.g. `dockyard.workspaceTabSnapshots`). The new key avoids
  clashing with the existing lossy `dockyard.workspaceTabs` payload, which is simply abandoned
  (old data decays; a failed decode is treated as "no saved state").
- Write the persisted snapshot on the same events that already update the in-memory snapshot:
  the private `saveTabSnapshot()` path (tab add/close), `.onChange(of: activeTab)`, and
  `.onDisappear`. In practice: wherever the in-memory `saveTabSnapshot(for:snapshot:)` is called,
  also persist to disk. Keeping both in lock-step avoids divergence.
- The lossy `WorkspaceStateStore` / `RestorableWorkspaceTab` becomes redundant for restore and is
  removed (or reduced to nothing) once the full store is the source of truth across restarts.

### Restore path

- `startupWorkspaceTabState` is updated so that when the in-memory snapshot is absent, it reads
  the **persisted full snapshot** and rebuilds the tab list, active tab, counts, titles, and
  editor file paths — instead of the current Info/Agent-only fallback.
- Fix the existing inconsistency in `startupWorkspaceTabState`: the snapshot branch currently
  filters the tab list to Info/Agent/Terminal/Browser and **drops Editor tabs**. The restore must
  handle all tab types uniformly (Info, Agent, Terminal, Browser, Editor).
- The surfaces/tab contents re-create lazily per workstream, and only for the workstream actually
  being viewed (`detailView` builds a single `TerminalContainerView` keyed by `.id(workstreamID)`),
  so relaunch cost is bounded — restoring does not eagerly spawn every workstream's tabs.

### Restore fidelity

- **Terminal tabs** → recreated as fresh shells. Deterministic derived IDs match the persisted
  list. Scrollback is not restored.
- **Editor tabs** → reopened at the saved file path (already captured in
  `WorkspaceTabSnapshot.editorFilePaths`).
- **Browser tabs** → recreated pointing at the default (port) URL. Arbitrary navigated URLs are
  not persisted (out of scope).

## Data Flow

- Single source of truth for a workstream's tab layout: `WorkspaceTabSnapshot`.
- In-memory cache (`TerminalSurfaceCache.tabSnapshots`): fast path within a session; carries live
  surface reconciliation.
- Persistent store (`dockyard.workspaceTabSnapshots`): survives restart.
- **On save:** write both in-memory and disk.
- **On restore:** prefer in-memory (reconciled against live surfaces); fall back to the persisted
  snapshot (rebuild tabs) when in-memory is absent (i.e. after a relaunch).

## Edge Cases & Error Handling

- **Corrupt / undecodable persisted snapshot** → fall back to `[.info, .agent]` with active tab
  `.info`.
- **Active tab references a tab that cannot be recreated** → fall back to `.info` (deliberately
  not `.agent`, to honor "remember where I was"). Note: a previously-active *terminal* is
  recreated as a fresh shell, so it remains selected rather than falling back.
- **Stale dead-terminal reconciliation within a session** is unchanged: `reconciled()` still drops
  dead terminals and falls back to `.agent` for that specific in-session case. (Optional cleanup:
  align this fallback to `.info` as well for consistency — called out for the plan, not required.)
- **Archived workstream** → also remove its persisted snapshot, alongside the existing in-memory
  `removeTabSnapshot(for:)`.
- **Old `dockyard.workspaceTabs` data** → ignored; not migrated.

## Testing

Extend `Tests/WorkspaceTabStateTests.swift` (existing pure-function test style):

- **Codable round-trip** of `WorkspaceTabSnapshot` covering all tab types (Info, Agent, Terminal,
  Browser, Editor), asserting tabs, active tab, counts, titles, and editor paths survive
  encode/decode.
- **`startupWorkspaceTabState` from a persisted snapshot** rebuilds Terminal/Browser/Editor tabs
  and preserves the active tab (including an Editor active tab — guards against the dropped-editor
  regression).
- **Active tab fallback**: a persisted snapshot whose active tab cannot be recreated resolves to
  `.info`, not `.agent`.

The Part 1 change (removing the on-selection `.focusAgent` post) is a notification side-effect
and is verified manually / by integration: switch A → B (on a non-Agent tab) → A and confirm each
returns to its own last tab; then quit and relaunch and confirm the same.

## Affected Files

- `Sources/Views/ContentView.swift` — remove on-selection `.focusAgent` post.
- `Sources/Views/TerminalContainerView.swift` — `Codable` for `WorkspaceTab` /
  `WorkspaceTabSnapshot`; new persistent snapshot store; persist on save events; rewrite
  `startupWorkspaceTabState` restore (all tab types); archive cleanup.
- `Tests/WorkspaceTabStateTests.swift` — new tests above.
- `DockyardApp.swift` — no change (Cmd+Return `.focusAgent` stays); listed for confirmation only.
