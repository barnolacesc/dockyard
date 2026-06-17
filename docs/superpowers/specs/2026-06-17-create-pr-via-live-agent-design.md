# Create PR & Commit via the live agent

**Date:** 2026-06-17
**Status:** Approved, ready for implementation plan

## Problem

The toolbar quick actions **Commit** and **Create PR** currently spawn a headless,
one-shot coding-CLI subprocess to do their work. For Claude this is effectively:

```
zsh -lic 'claude -p "<prompt>" --output-format json --continue --fork-session
  --no-session-persistence --dangerously-skip-permissions'
```

This design is dangerous and opaque:

- **`--dangerously-skip-permissions`** removes every approval gate.
- It runs via a full login+interactive shell (`zsh -lic`), so it inherits the user's
  entire environment, credentials, PATH, and network access.
- It reads untrusted repo content (the diff, files) to write the commit/PR text — the
  classic prompt-injection surface — while permission-less.
- The headless run does **not** re-apply the "restrict to worktree" system prompt that
  the interactive agent gets, so it is actually *less* constrained than the live agent.
- It is **invisible**: output only appears in a debug panel that is off by default; the
  user normally sees only a 3-second ✓ or ✗.

## Goal

Replace the headless subprocess for **Commit** and **Create PR** with sending the prompt
directly into the **live Coding Agent** in the workspace's Agent tab. The agent does the
work in view, under its own permission mode, with no `--dangerously-skip-permissions`.

**Push** and **Close PR** are direct `git`/`gh` commands with no LLM involvement and are
**out of scope** — they keep their current behavior via `QuickActionRunner`.

## Decisions (from brainstorming)

- **Both** Commit and Create PR are converted (identical dangerous pattern).
- **Auto-submit**: type the prompt into the agent and send Enter immediately.
- **No agent-busy detection**: if the agent is mid-task, the typed input simply queues as
  the next message in the conversation. Timing the click is the user's responsibility.
- **CLI-agnostic**: the prompt is plain typed input, so it works for any agent CLI
  (Claude, Codex, Gemini, OpenCode) without per-CLI special-casing.

## Approach

**Parent-owned send closure.** Direct actions (Push, Close PR) keep flowing through
`QuickActionRunner`. The two agent-delegated actions (Commit, Create PR) call a new
`onSendToAgent` closure provided by `TerminalContainerView`, which focuses the Agent tab
and types the prompt into the live surface. This keeps the runner about subprocesses and
keeps terminal typing in the view that owns the surface cache.

Rejected alternative: routing everything through `QuickActionRunner` with an
`onSendToAgent` hook — that forces the runner to know about Ghostty surfaces, which is not
its responsibility.

## Behavior

Clicking **Commit** or **Create PR**:

1. Switches the workspace to the **Agent** tab (`activeTab = .agent`).
2. Types the action's prompt into the live Coding Agent surface
   (`surfaceCache.sendText(to: agentID, text: prompt + "\r")`).
3. The trailing carriage return submits it as a message; the agent does the work in view.

No subprocess is spawned, no `--dangerously-skip-permissions`, and the action runs under
whatever permission mode the live agent is already using.

## Prompts (reused unchanged)

- **Commit:** "Stage and commit all changes in the working tree with a good commit message
  based on the changes. Do not push."
- **Create PR:** "Create a pull request for the current changes. Write a clear title and
  description based on what we've been working on."

These remain `QuickAction.prompt`.

## Code changes

### `Sources/Models/QuickActionRunner.swift`
- Rename `QuickAction.usesLLM` → `delegatesToAgent` (cases unchanged: `commit`, `createPR`).
- Delete `runLLMAction(...)`.
- In `run(...)`, remove the `.commit, .createPR` branch — those actions no longer go
  through the runner. Keep `.push` (`runPush`) and `.closePR` (`runClosePR`).
- Remove now-unused parameters from `run(...)` if they are only used by the deleted LLM
  branch (`codingCLI`, `codingCLIPath`). `ghPath`/`branchName` stay for Close PR.
- `onSuccess` still fires for Push and Close PR.

### `Sources/Models/CommandBuilder.swift`
- Delete `CodingCLICommandBuilder.buildQuickActionCommand(...)` and the
  `CLIQuickActionCommand` struct — both become unused.

### `Sources/Views/TerminalContainerView.swift`
- Add an `onSendToAgent: (QuickAction) -> Void` to `GitHubActionMenu` and pass it from the
  toolbar call site. Implementation:
  ```swift
  onSendToAgent: { action in
      guard let prompt = action.prompt else { return }
      activeTab = .agent
      surfaceCache.sendText(to: agentID, text: prompt + "\r")
  }
  ```
- `GitHubActionMenu.runAction(_:)`: if `action.delegatesToAgent`, call `onSendToAgent(action)`
  instead of `runner.run(...)`.
- `GitHubActionMenu.disabledReason(for:)`: remove the `action.usesLLM` branch (the
  coding-CLI-installed and bypass-permissions checks). Delegated actions are no longer
  disabled on those grounds. Keep the Close PR `gh`-installed check.
- Remove `codingCLI`, `codingCLIPath`, and `bypassPermissions` from `GitHubActionMenu` if
  nothing else in the view uses them after the change (verify at implementation).
- The runner's spinner/✓/✗ state naturally no longer animates for the delegated actions
  (they don't touch runner state). The tab switch + visibly typed prompt is the feedback.
  No special handling needed in `label(for:)`.
- `onSuccess` closure (the `createPR`/`closePR` refresh block): the `createPR` path no
  longer fires (it doesn't go through the runner). The Close PR refresh stays. The new PR
  is picked up by the existing ~15s GitHub poll, which flips the button to "Open #N".

### `Sources/Views/SettingsView.swift` + locale files
- The quick-action debug-panel description currently reads
  "Show a debug panel with command output from quick actions (Create PR, Commit & Push)."
  Update it so it no longer lists the removed actions (e.g. drop the parenthetical, or list
  only "Push & Close PR"). Update all 5 locale files (en, ca, de, es, sv).

### Tests
- Delete `Tests/CommandBuilderTests.swift::testBuildCodexQuickActionCommandUsesExec`.
- Add coverage:
  - `QuickAction.delegatesToAgent` is `true` for `.commit`/`.createPR`, `false` for
    `.push`/`.closePR`.
  - `QuickAction.prompt` returns the expected text for `.commit`/`.createPR` and `nil` for
    `.push`/`.closePR`.
  - `disabledReason` no longer gates delegated actions on bypass-permissions / CLI install.
  - The terminal typing path (`sendText`) is UI/Ghostty-bound and not unit-tested; keep the
    testable logic (mapping + gating) in pure functions.

## Explicitly dropped

- The headless `claude -p … --dangerously-skip-permissions` execution for both actions.
- The bypass-permissions requirement for Commit and Create PR.
- The instant GitHub-info refresh after Create PR (replaced by the existing poll).

## Edge cases

- **Agent surface not alive** (workspace not started, or agent exited via Ctrl+D):
  `sendText` guards on `surfaces[surfaceID]` and silently no-ops. v1 accepts this. A
  future improvement could respawn the agent and send after it is ready, but that is racy
  and out of scope here.
- **Submit key:** the prompts are single-line, so a trailing `\r` submits cleanly in the
  agent TUI. Verify during implementation that one carriage return submits (not just
  inserts a newline) in the target CLIs.

## Out of scope

- Push and Close PR behavior.
- Agent busy/idle detection.
- Respawning a dead agent before sending.
- Any change to the prompt text.
