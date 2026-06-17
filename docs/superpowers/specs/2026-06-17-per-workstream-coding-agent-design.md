# Per-Workstream Coding Agent

**Date:** 2026-06-17
**Status:** Approved design

## Problem

Dockyard currently has a single global setting (`dockyard.codingCLI`) that picks
which coding agent every workstream uses (Claude Code, Codex, OpenCode, Gemini
CLI). Users want to choose the coding agent **per workstream** so different
workstreams in the same project can run different agents.

## Goals

- Each workstream can override which coding agent it uses.
- An unset workstream follows the global default, so existing behavior is
  unchanged until a user opts in.
- The override is editable at any time (not just at creation) from the
  workstream's Info tab.
- No data migration breakage for existing persisted workstreams.

## Non-Goals

- Removing or replacing the global Settings picker (it stays as the default).
- Per-workstream overrides of *other* agent settings (tmux, bypass permissions,
  agent teams, etc.) — out of scope.
- Changing how any individual CLI's command is built.

## Decisions

- **Picker location:** the workstream **Info tab** (Cmd+1), as a new "Coding
  Agent" section. One keystroke away and consistent with the existing
  per-workstream info/settings surface.
- **Relationship to global setting:** the global Settings picker remains the
  default. The per-workstream picker offers **"Use Default (…)"** plus the four
  CLIs. A workstream with no explicit choice follows global; existing
  workstreams follow global until changed (migration-safe).

## Architecture

### 1. Data model — `Sources/Models/Project.swift`

Add one optional field to `Workstream`:

```swift
var codingCLI: String?   // nil = follow global default; else a CodingCLI rawValue
```

- `Optional` makes Codable decoding migration-safe: persisted workstreams that
  predate this field decode to `nil` (Swift synthesizes `decodeIfPresent` for
  optionals), so no custom decoder or data migration is needed.
- `init` gains `codingCLI: String? = nil`. New workstreams default to `nil`
  (follow global). No seeding from the global value is required.

### 2. Resolution — reuse existing `ToolStatus.resolvedCodingCLI(storedValue:)`

No change to the resolution logic. A small pure helper computes the effective
stored value — the workstream override when present and non-empty, otherwise the
global setting:

```swift
// Sources/Models/CommandBuilder.swift (next to CodingCLI)
func effectiveCodingCLIRaw(workstream: String?, global: String) -> String {
    if let ws = workstream, !ws.isEmpty { return ws }
    return global
}
```

`TerminalContainerView` then resolves the agent from that value:

```swift
let effective = effectiveCodingCLIRaw(workstream: workstreamCodingCLI, global: codingCLIRaw)
let selectedCodingCLI = appEnv.toolStatus.resolvedCodingCLI(storedValue: effective)
```

`resolvedCodingCLI` already maps an empty/unknown `storedValue` to the
auto-detected first-installed CLI, so the existing fallback chain is preserved.

All downstream derivations already flow from `selectedCodingCLI`
(`selectedCodingCLIPath`, `supportsSessionName(for:)`, `supportsAgentTeams`,
`supportsAutoRenameBranch`, command building, and launch logging via
`agentCLI:`), so they pick up the per-workstream value automatically.

### 3. Plumbing — `ContentView` → `TerminalContainerView`

- In `ContentView.detailView`, compute the workstream's index and build a
  `Binding<String?>` into the project store:

  ```swift
  let codingCLIBinding = Binding<String?>(
      get: { projectList.items[projectIndex].workstreams[wsIndex].codingCLI },
      set: { projectList.items[projectIndex].workstreams[wsIndex].codingCLI = $0 }
  )
  ```

  Writing through this binding mutates `projectList.items`, which the existing
  debounced `onChange(of: projectList.items)` persists via `ProjectStore.save`.

- Pass it to `TerminalContainerView` as a new `@Binding var workstreamCodingCLI:
  String?` parameter.

- `TerminalContainerView` keeps reading the global
  `@AppStorage("dockyard.codingCLI")` (`codingCLIRaw`) and now also the binding.
  `selectedCodingCLI` is computed from `effectiveCodingCLIRaw`.

- Replace the existing `onChange(of: codingCLIRaw)` handler with
  `onChange(of: effectiveCodingCLIRaw)` performing the same work
  (`removeSurface(for: agentID)` → `rebuildAgentCommand()` → `preloadSurfaces()`).
  This means:
  - Changing the per-workstream override restarts that workstream's agent.
  - Changing the global setting restarts only workstreams that follow the
    global (an overridden workstream's effective value is unchanged, so it is
    left alone — fixing the wasteful restart that a raw `codingCLIRaw` observer
    would cause).

### 4. UI — `WorkstreamInfoView`

Add a "Coding Agent" `Section` (placed near the other workstream metadata) with
a `Picker` bound to the new `Binding<String?>`:

- Option "Use Default (\<global display name\>)" tagged `String?.none`, where the
  display name is `toolStatus.resolvedCodingCLI(storedValue: globalCodingCLIRaw).displayName`.
- One option per `CodingCLI.allCases`, tagged by `rawValue` (as `String?`).
- A caption noting that "Use Default" follows the global Settings choice.
- If the resolved CLI for this workstream is not installed
  (`toolStatus.status(for:).isInstalled == false`), show an inline warning
  reusing `CodingCLI.missingTitle` / install link, consistent with the agent
  tab's existing not-installed state.

`WorkstreamInfoView` already has `@EnvironmentObject var appEnv`, so tool status
and the global `@AppStorage("dockyard.codingCLI")` are available here.

### 5. Settings — `SettingsView`

Keep the global "Coding CLI" `Picker` unchanged in behavior. Update its help/
footer text to clarify it is the **default for workstreams that haven't chosen
their own** agent. The capability-dependent toggles (agent teams, auto-rename)
continue to key off the global `selectedCodingCLI` in this view, which is the
correct context for the global default.

### 6. Localization

New user-facing strings added to all five locale files (en, ca, de, es, sv):

- "Coding Agent" (section title)
- "Use Default (%@)" (picker default row)
- The caption explaining the default behavior
- Any new Settings help text

### 7. Testing (TDD)

- **`effectiveCodingCLIRaw(workstream:global:)`** (new helper):
  - override present → returns override
  - override `nil` → returns global
  - override `""` → returns global
- **Resolution end-to-end** via `resolvedCodingCLI` with the effective value:
  workstream override wins over global; `nil` override resolves to global;
  unknown/empty resolves through the auto-detect chain.
- **Codable migration** (`ProjectTests`): decoding a `Workstream` JSON blob that
  omits `codingCLI` yields `nil` and round-trips; encoding a set value
  round-trips.

Tests live in `Tests/CommandBuilderTests.swift` (helper/resolution) and
`Tests/ProjectTests.swift` (model/Codable), matching existing coverage.

## Data Flow Summary

```
Settings global picker ──(dockyard.codingCLI)──┐
                                               ▼
Info tab picker ──(Binding<String?>)──► Workstream.codingCLI ──► ProjectStore (UserDefaults)
                                               │
ContentView builds Binding ────────────────────┘
                                               ▼
TerminalContainerView: effectiveCodingCLIRaw = override ?? global
                                               ▼
                       selectedCodingCLI (resolvedCodingCLI)
                                               ▼
        command building · path · session name · launch log · capability flags
```

## Risks / Notes

- Index-based binding in `ContentView` must guard against a stale workstream
  index (recompute from the current `projectList.items`); the workstream branch
  already resolves `activeWorkstream` by id, so the index lookup uses the same id.
- The agent surface restart on effective-value change reuses the existing,
  proven `removeSurface → rebuild → preload` path; no new lifecycle logic.
