# Agent permission modes design

Date: 2026-06-29
Branch: `count-async-core`

## Purpose

Dockyard has a per-workstream "Bypass permission prompts" toggle, but the
meaning is inconsistent across Coding CLIs and incomplete for Codex:

- Claude Code gets its real dangerous bypass mode through
  `--dangerously-skip-permissions`.
- Codex only gets `--ask-for-approval never`; this disables prompts but does
  not necessarily remove the sandbox unless the separate "Allow writes outside
  worktree" setting also enables `--sandbox danger-full-access`.
- The running agent does not change when the toggle changes. Dockyard only
  rebuilds the command used for the next launch or respawn.
- Claude Code and Codex both have native ways to adjust permissions during a
  running interactive session, but Dockyard does not expose them.

This spec defines the intended product semantics and the implementation shape
for a later development pass.

## Sources checked

- OpenAI Codex CLI reference:
  <https://developers.openai.com/codex/cli/reference>
- OpenAI Codex approvals and sandboxing:
  <https://developers.openai.com/codex/agent-approvals-security>
- OpenAI Codex slash commands:
  <https://developers.openai.com/codex/cli/slash-commands>
- Claude Code CLI reference:
  <https://code.claude.com/docs/en/cli-reference>
- Claude Code permission modes:
  <https://code.claude.com/docs/en/permission-modes>
- Local `codex --help`, `codex resume --help`, and `codex exec --help`
- Local `claude --help` and `claude --version` (`2.1.195`)

## Product semantics

### Rename the concept

The UI should stop presenting this as a soft "bypass permission prompts"
setting. The behavior is dangerous enough that the user-facing label should be:

> Dangerously skip permissions

The description should say that this grants the Coding Agent the selected CLI's
full dangerous autonomy mode. For Codex and Claude Code, this means it can run
commands and edit without approval prompts; Codex also runs without sandboxing
when this mode is active.

The existing storage key can remain `dockyard.bypassPermissions` and
`Workstream.bypassPermissions` to avoid migration churn. Only the display text
and command mapping need to change.

### Relationship to "Allow writes outside worktree"

"Allow writes outside worktree" remains a separate setting for normal sessions.
It controls the broad filesystem boundary when the agent is not in dangerous
bypass mode:

- Codex with bypass off:
  - outside writes off -> `--sandbox workspace-write --ask-for-approval on-request`
  - outside writes on -> `--sandbox danger-full-access --ask-for-approval on-request`
- Claude Code with bypass off:
  - outside writes off -> Dockyard injects the restrict-to-worktree system prompt
  - outside writes on -> Dockyard omits that prompt

When "Dangerously skip permissions" is on, it supersedes "Allow writes outside
worktree":

- Codex should use `--dangerously-bypass-approvals-and-sandbox` (or `--yolo`),
  not merely `--ask-for-approval never`.
- Claude Code should use `--permission-mode bypassPermissions` or the
  equivalent `--dangerously-skip-permissions`.

The settings UI should make this dependency visible. When dangerous bypass is
enabled, "Allow writes outside worktree" should either be disabled or show a
caption explaining that it is ignored because the agent is already in full
dangerous mode.

### Mid-session behavior

Changing a Dockyard setting cannot by itself rewrite the permission policy of
an already-running CLI process. Dockyard should make that clear and offer a
native in-agent control for the current session.

The workstream Info panel should distinguish two actions:

1. Persistent setting toggle:
   - Saves the workstream default.
   - Applies automatically to the next agent start or respawn.
2. Live permission action:
   - Opens or cycles the current agent's native permission control.
   - Applies to the currently running terminal session only after the CLI
     accepts the change.

For Codex, the live action should focus the Agent tab and send:

```text
/permissions
```

followed by Return. Codex owns the selector and any confirmation flow.
Dockyard should not assume undocumented keystrokes to choose a specific mode.

For Claude Code, Dockyard should launch non-bypass sessions with:

```text
--allow-dangerously-skip-permissions
```

This enables `bypassPermissions` in Claude Code's Shift+Tab cycle without
starting in bypass mode. The live action should focus the Agent tab and send the
terminal key sequence for one Shift+Tab as a best-effort shortcut into Claude
Code's native mode cycle. If reliable synthetic Shift+Tab injection is not
possible with the current Ghostty wrapper, or if the implementation cannot
verify that the key event was sent, the first implementation should instead
show a localized hint in the Info panel:

> Press Shift+Tab in the Agent tab to switch permission modes.

That fallback is acceptable because the launch flag is what makes the mode
available mid-session.

For OpenCode and Gemini, Dockyard should keep the persistent toggle disabled or
mark it unsupported until their interactive permission semantics are verified.
Do not silently ignore a dangerous permission toggle.

## Command mapping

### Claude Code

Current behavior:

```text
claude --resume <workstream-id> [--dangerously-skip-permissions]
claude --session-id <workstream-id> [--dangerously-skip-permissions]
```

Target behavior:

- If dangerous bypass is off:
  - Add `--allow-dangerously-skip-permissions` so the user can switch into
    bypass mode later from the live session.
  - Keep the existing restrict-to-worktree prompt when outside writes are off.
- If dangerous bypass is on:
  - Prefer `--permission-mode bypassPermissions` for explicitness.
  - `--dangerously-skip-permissions` is still acceptable because Claude Code
    documents it as equivalent.
  - Do not also add `--allow-dangerously-skip-permissions`; it is redundant.

The implementation may keep the old flag if it reduces churn, but tests should
assert the semantic mode, not the exact alias, unless the code chooses one
canonical representation.

### Codex

Current behavior:

```text
codex resume --last -C <dir> --sandbox <workspace-write|danger-full-access> --ask-for-approval <on-request|never>
codex -C <dir> --sandbox <workspace-write|danger-full-access> --ask-for-approval <on-request|never>
```

Target behavior:

- If dangerous bypass is off:
  - Keep explicit `--sandbox workspace-write` or `--sandbox danger-full-access`
    based on "Allow writes outside worktree".
  - Keep `--ask-for-approval on-request`.
- If dangerous bypass is on:
  - Use `--dangerously-bypass-approvals-and-sandbox` for both resume and fresh
    commands.
  - Keep `-C <dir>`.
  - Do not also pass `--sandbox` or `--ask-for-approval`; the dangerous flag is
    clearer and avoids contradictory command lines.
- Keep `--dangerously-bypass-hook-trust` separate. It only controls hook trust
  and must not be treated as a permissions bypass.

Use the long flag in generated commands rather than `--yolo`. The long flag is
self-documenting in launch logs and error views; docs identify `--yolo` as an
alias.

## UI design

### Settings

In Settings > Coding Agent:

- Rename "Bypass permission prompts" to "Dangerously skip permissions".
- Warning description:

  > Starts Coding Agents in their full dangerous mode. Claude Code uses
  > bypassPermissions. Codex bypasses approvals and sandboxing. Use only for
  > trusted workstreams.

- If selected CLI is OpenCode or Gemini, show a warning that dangerous
  permission mode is not wired for that CLI yet and the setting only applies to
  supported CLIs. A later CLI adapter can replace this with verified behavior.

### Workstream Info

In the workstream Info panel:

- Rename the toggle to "Dangerously skip permissions".
- Replace the current "Applies the next time the agent starts" copy with two
  pieces of UI:
  - A caption: "Saved for the next Coding Agent start."
  - A button: "Change live permissions..." when the current CLI supports a live
    native control.
- Button behavior:
  - Codex: focus the Agent tab, send `/permissions\r`.
  - Claude Code: focus the Agent tab and either send Shift+Tab, or show the
    localized Shift+Tab hint if key injection is not reliable.
  - Unsupported CLIs: hide the button or show disabled help.

The button should not change `Workstream.bypassPermissions` by itself. It is a
runtime action. The persistent toggle controls future launches.

## Implementation outline

### Command builder

Update `CodingCLICommandBuilder`:

- Extract Claude permission flag selection into a helper.
- Extract Codex permission flag selection into a helper.
- Codex helper returns either:
  - dangerous bypass flag only, or
  - explicit sandbox plus approval policy.
- Claude helper returns either:
  - `--permission-mode bypassPermissions`, or
  - `--allow-dangerously-skip-permissions`.

Tests should cover fresh and resume commands for:

- Claude bypass off, outside writes off.
- Claude bypass off, outside writes on.
- Claude bypass on.
- Codex bypass off, outside writes off.
- Codex bypass off, outside writes on.
- Codex bypass on.

### Live session permissions

Add a small agent-neutral API in `TerminalContainerView`:

```swift
private func openLivePermissionControl()
```

Behavior:

- Guard that the Agent surface exists.
- Set `activeTab = .agent`.
- Switch on `selectedCodingCLI`.
- Codex sends `/permissions\r` through `surfaceCache.sendText(to:text:)`.
- Claude calls a new `surfaceCache.sendShiftTab(to:)` if the lower terminal
  layer can implement it. If not, set a transient localized hint visible in the
  Info panel.
- Unsupported CLIs show a localized unavailable hint.

If synthetic Shift+Tab support is added, keep it isolated in
`TerminalSurfaceCache` and `TerminalView`. Do not spread Ghostty key event
construction through SwiftUI views.

### Localization

Every new user-facing string must be added to all five locale files:

- `Localization/en.lproj/Localizable.strings`
- `Localization/ca.lproj/Localizable.strings`
- `Localization/de.lproj/Localizable.strings`
- `Localization/es.lproj/Localizable.strings`
- `Localization/sv.lproj/Localizable.strings`

Use "directory", "Coding Agent", and "workstream" consistently.

## Error handling

- If a CLI rejects a flag, the existing terminal launch failure UI should show
  the generated command. This is enough for initial implementation.
- If Codex opens `/permissions` but the user cancels, Dockyard does not need to
  track that. The CLI remains source of truth for runtime mode.
- If Claude Shift+Tab injection is unavailable or fails, Dockyard should show
  the manual hint and leave the persistent setting unchanged.
- If a managed policy blocks Codex yolo or Claude bypass mode, Dockyard should
  not try to work around it. The CLI error or in-agent message is authoritative.

## Out of scope

- Designing OpenCode or Gemini permission adapters.
- Adding an external Dockyard sandbox for Claude Code.
- Persisting the live runtime permission state back into Dockyard.
- Replacing each CLI's native permission picker with Dockyard's own permission
  UI.
- Changing quick actions, except that their docs should continue to say they
  run through the live agent rather than a separate dangerous subprocess.

## Verification plan

- Add unit tests for `CodingCLICommandBuilder` command strings.
- Run `./scripts/dev.sh test`.
- Run `./scripts/dev.sh br` and verify:
  - Claude bypass-off launch includes the allow flag.
  - Claude bypass-on launch starts in bypass mode.
  - Codex bypass-off launch uses explicit sandbox and `on-request`.
  - Codex bypass-on launch uses `--dangerously-bypass-approvals-and-sandbox`.
  - The Info panel live action opens Codex `/permissions`.
  - The Claude live action either cycles permission mode or shows the manual
    Shift+Tab hint.

## Follow-up implementation plan

The implementation should be split into three tasks:

1. Command builder semantics and tests.
2. UI copy/localization and "ignored while dangerous mode is on" state.
3. Live permission control for Codex and Claude Code, with Shift+Tab injection
   only if the terminal layer can implement it cleanly.
