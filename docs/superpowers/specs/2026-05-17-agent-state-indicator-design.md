# Reliable Agent State Indicator — Design

**Status:** Draft
**Date:** 2026-05-17
**Branch:** `dy/push-deep-kq`

## Problem

The pulsing dot beside each workstream in the sidebar is meant to communicate the Coding Agent's status, but it isn't reliable. Today it is driven by two indirect proxies:

- **`isActive`** (pulsing green) — Ghostty's `GHOSTTY_ACTION_SET_TITLE` posting `.terminalTitleChanged` (see `Sources/Terminal/TerminalApp.swift:59-71`). This actually means "the terminal title changed in the last 5 seconds," which only correlates loosely with agent activity. A long-thinking agent that doesn't update its title looks idle.
- **`needsAttention`** (pulsing accent) — Ghostty's `GHOSTTY_ACTION_RING_BELL` posting `.terminalNeedsAttention` (see `Sources/Terminal/TerminalApp.swift:78-102`). Triggered by the BEL char, which different CLIs ring at different moments. Worse, it is **cleared on focus, typing, and mouse-down** (`Sources/Terminal/TerminalView.swift:172, 356, 649`), so simply *looking* at the workstream wipes the signal.

The result: the dot lies in both directions — it goes dark while the agent is still working, and it clears as soon as the user glances at the workstream.

## Goal

Replace the indirect heuristics with an authoritative agent-lifecycle signal sourced from the Coding Agent itself, so the sidebar dot reflects three real states:

- **working** — agent is processing a turn (pulsing green)
- **waiting** — agent is blocked on the user (pulsing accent)
- **idle** — agent finished its turn or is not running (static gray)
- **unknown** — no telemetry available (no dot drawn)

Non-goals: a "completed" state distinct from idle; surfacing state anywhere other than the sidebar; replacing the desktop notification on BEL; overlaying run-script state on the same indicator.

## Design

### State model and visual mapping

A new `AgentState` enum is the single source of truth for the indicator.

| `AgentState` | Sidebar dot |
| --- | --- |
| `working` | pulsing green (existing `isActive` visual) |
| `waiting` | pulsing accent (existing `needsAttention` visual) |
| `idle` | static gray dot |
| `unknown` | no dot drawn (12pt frame preserved so headlines don't shift) |

The orange `exclamationmark.triangle` for an invalid worktree path continues to win over all agent states — that signal is about the worktree, not the agent.

Critically, **attention is no longer cleared by focus, typing, or mouse events**. The state only flips out of `waiting` when the agent itself reports `working` (i.e. a new turn started because the user's message was accepted). This fixes the "indicator clears when I look at it" failure mode.

A freshly-created workstream whose Agent tab has never launched shows no dot. As soon as the agent boots and its first hook fires, the dot appears. This is intentional: no dot means "nothing to know yet."

### State files

Each workstream's current state lives in a JSON file at:

```
~/Library/Caches/dockyard/agent-state/<workstream-uuid>.json
```

This mirrors the existing run-state convention (`~/Library/Caches/dockyard/run-state/<wsID>.json`) so the file-watching plumbing — FSEvents → published store → SwiftUI binding — is already proven by `RunState.swift`.

File format:

```json
{
  "state": "working",
  "updatedAt": "2026-05-17T14:32:11Z",
  "pid": 48211
}
```

`pid` lets the app detect stale files on launch: if the recorded pid is dead, the file is treated as `unknown` and overwritten. `updatedAt` is diagnostic only.

### Helper binary

A small Swift executable `dy-agent-state` is bundled at `Contents/Helpers/dy-agent-state` (same convention as `dy-run`). It is invoked by Coding Agent hooks, writes the appropriate state file, and exits. CLI shape:

```
dy-agent-state --workstream-id <uuid> --state working
dy-agent-state --workstream-id <uuid> --state waiting
dy-agent-state --workstream-id <uuid> --state idle
```

The hook payload on stdin is ignored — the workstream UUID and target state are passed as arguments, baked in at settings-file-generation time. This keeps the helper trivial and CLI-agnostic.

### App-side reader

A new `AgentStateStore: ObservableObject` lives in `Sources/Models/`, modeled directly on `RunState.swift`:

- Watches `~/Library/Caches/dockyard/agent-state/` via FSEvents.
- Parses each state file into `[UUID: AgentState]`.
- Publishes the dictionary; sidebar reads it the same way it currently reads `WorkstreamActivityTracker`.
- On startup, performs the stale-pid scan described above.

### Wiring hooks into the agent launch

For each workstream that uses a hook-capable CLI, Dockyard writes a per-workstream settings file at:

```
~/Library/Caches/dockyard/claude-settings/<workstream-uuid>.json
```

The file embeds the workstream UUID directly into each hook command so the helper doesn't need to discover its context:

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state --workstream-id <UUID> --state working"
      }]
    }],
    "Notification": [{
      "hooks": [{
        "type": "command",
        "command": "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state --workstream-id <UUID> --state waiting"
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state --workstream-id <UUID> --state idle"
      }]
    }]
  }
}
```

The file is regenerated on every Agent launch (cheap, idempotent) so the bundled helper path stays correct after app moves and updates.

`TerminalContainerView.buildClaudeCommand()` adds `--settings <path>` to the `claude` argv when:

- `selectedCodingCLI == .claudeCode`, AND
- a usable `dy-agent-state` helper exists in the bundle.

For other CLIs the flag is omitted, no settings file is generated, no state file is ever written, and the indicator stays in `unknown`.

Claude Code merges hook arrays from `--settings` with the user's `~/.claude/settings.json`, so Dockyard's hooks coexist with whatever the user has configured globally. If that assumption breaks on a future Claude Code version, Dockyard will merge the user's settings into its own at write time.

The new flag is orthogonal to `--append-system-prompt` — both can be passed together; the existing system-prompt assembly in `TerminalContainerView` does not change.

### Per-CLI matrix

| CLI | Hook support | Behavior |
| --- | --- | --- |
| Claude Code | Native (`UserPromptSubmit`, `Notification`, `Stop`) | Full lifecycle |
| Codex | None today | Indicator stays `unknown` (no dot). Revisit when/if hooks ship. |
| Future CLIs | Per-CLI capability check | Default to `unknown` until a per-CLI adapter is added |

The decision lives in a single helper: `func agentHookSettings(for cli: CodingCLI) -> URL?` returns a settings-file path for supported CLIs and `nil` otherwise. `buildClaudeCommand()` only appends `--settings` when this returns non-nil. Adding a new CLI is one switch case plus one settings template.

### Removals and call-site changes

This change is largely subtractive — reliability comes from deleting unreliable signal sources.

**Sources to delete:**

- `Sources/Terminal/TerminalApp.swift:81-86` — the `GHOSTTY_ACTION_RING_BELL` branch that posts `.terminalNeedsAttention`. The desktop-notification side-effect (lines 88-101) stays — OS notifications on bell are still useful.
- `Sources/Terminal/TerminalView.swift:172, 356, 649` — the three `.terminalClearAttention` posts (focus / typing / mouse-down). All deleted. Attention only clears when the agent itself reports `working`.
- `WorkstreamActivityTracker`'s subscriptions to `.terminalTitleChanged`, `.terminalNeedsAttention`, and `.terminalClearAttention` — leaning toward deleting the whole tracker once its API is unused, replacing `isActive(_:)` / `needsAttention(_:)` calls with `AgentStateStore.agentState(for:)`.

**Signals that stay:**

- `.terminalTitleChanged` notification — still used by the tab strip to populate `terminalTitles[surfaceID]`. The notification stays; only the activity-tracker subscriber goes.
- `terminalActivity` and `terminalChildExited` notifications — unrelated, untouched.

**Call sites to update:**

- `ActivityIndicator` (`ProjectSidebar.swift:1018-1056`) — signature changes from `(isActive: Bool, isPathValid: Bool, needsAttention: Bool)` to `(state: AgentState, isPathValid: Bool)`. The invalid-path branch is unchanged. The `unknown` branch returns `EmptyView()` inside a 12pt frame.
- `ProjectSidebar.swift:189` — the auto-scroll-on-attention logic. Replace `activityTracker.needsAttention(workstream.id)` with `agentStateStore.agentState(for: workstream.id) == .waiting`.
- `ProjectSidebar.swift:932, 951` — the accent-color overrides on the headline and subtitle. Same substitution.

**Lifecycle:**

- `WorkstreamArchiver` deletes `~/Library/Caches/dockyard/agent-state/<wsID>.json` and `~/Library/Caches/dockyard/claude-settings/<wsID>.json` alongside the run-state file when a workstream is archived.

No persisted on-disk state needs migrating — all the removed signals were in-memory only.

### Incremental rollout

The change lands as three PRs:

1. **PR 1 — Helper + store, no UI change.** Add the `dy-agent-state` executable target, the per-workstream settings.json writer, the `AgentStateStore` reader, and the `--settings` flag in `buildClaudeCommand()`. Indicator code untouched. Verify state files appear and update correctly during real agent usage before flipping the UI.
2. **PR 2 — Indicator cutover.** Swap `ActivityIndicator` to take `AgentState`. Swap call sites in `ProjectSidebar`. Remove the bell/focus/typing/mouse-down clearing in `TerminalApp.swift` and `TerminalView.swift`. This is the user-visible change.
3. **PR 3 — Cleanup.** Delete `WorkstreamActivityTracker` if it ends up empty. Drop dead notification name declarations. Update `HelpView` if the indicator is documented there.

PR 1 is safely shippable on its own (zero UX impact). PR 2 needs real-world soak; its worst failure mode is "indicator stuck in waiting," which is annoying but not destructive.

## Risks and open questions

- **Claude Code `--settings` semantics.** Design assumes `--settings` merges with `~/.claude/settings.json` rather than replacing it. PR 1 will verify this against the targeted Claude Code version; if the assumption is wrong, the writer reads the user's settings and merges at generation time.
- **Hook command path stability.** The settings file embeds an absolute path to `Contents/Helpers/dy-agent-state`. Regenerating the file on every Agent launch keeps it correct after the app is moved or replaced by Sparkle. Stale files from a previous app location resolve themselves on next launch.
- **Multiple Agent tabs in one workstream.** All Agent surfaces in a workstream share the same `--settings` (same UUID), so they overwrite the same state file. Behaviorally fine: any one of them being `working` means the workstream is `working`. If we ever split state per-surface, the file naming will need to change.
- **Stale state across app restart.** Handled by the pid liveness check on `AgentStateStore` startup. If the helper writes the file but the agent later crashes without a hook firing, the indicator can sit on a wrong state until the workstream is reopened. Acceptable for v1; revisit if it becomes a problem.

## File summary

New:

- `Sources/Models/AgentState.swift` — enum + Codable
- `Sources/Models/AgentStateStore.swift` — FSEvents-backed publisher (modeled on `RunState.swift`)
- `Sources/Models/AgentHooks.swift` — generates the per-workstream settings.json, owns `agentHookSettings(for:)`
- New executable target `dy-agent-state` (sources under e.g. `Helpers/AgentState/`)

Modified:

- `Sources/Views/TerminalContainerView.swift` — `buildClaudeCommand()` adds `--settings` when applicable
- `Sources/Views/ProjectSidebar.swift` — `ActivityIndicator` signature, call sites for accent overrides and auto-scroll
- `Sources/Terminal/TerminalApp.swift` — remove the BEL → `.terminalNeedsAttention` post (keep desktop notification)
- `Sources/Terminal/TerminalView.swift` — remove the three `.terminalClearAttention` posts
- `Sources/Models/WorkstreamArchiver.swift` — delete agent-state and claude-settings files on archive
- `project.yml` — declare the new helper target and bundle it under `Contents/Helpers/`

Deleted (in PR 3):

- `Sources/Models/WorkstreamActivityTracker.swift` (if fully unused)
- Notification name declarations for `terminalNeedsAttention` and `terminalClearAttention`
