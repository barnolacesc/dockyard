# Agent portability audit

Date: 2026-06-18
Branch: `route-stale-reg`

## Purpose

Dockyard now supports multiple Coding CLI choices (`claude`, `codex`,
`opencode`, and `gemini`), but several features were originally built around
Claude Code. This audit lists the current Claude-specific or Claude-biased
behavior, whether each item can be ported to other agents, and which follow-up
specs are needed.

This is an audit, not an implementation spec. Each item that needs product or
adapter design should get a separate design document before implementation.

## Summary table

| Feature area | Current status | Portability |
|---|---|---|
| Sidebar agent state / workstream colors | Claude-only state source | Codex: ready to spec/implement. OpenCode: research. Gemini: unverified. |
| Auto-rename branch + task description | Prompt injected only for Claude | Codex: feasible via `developer_instructions`. OpenCode: feasible via generated config/agent prompt. Gemini: unverified. |
| Restrict writes to worktree | Claude prompt, Codex sandbox, ignored by generic CLIs | Needs unified per-CLI policy semantics. |
| Agent Teams | Claude-only toggle + env + `--teammate-mode tmux` | Codex has native multi-agent tools but different semantics. OpenCode has subagents but different config. Needs redesign. |
| Permission bypass | Claude and Codex implemented; OpenCode/Gemini ignored | OpenCode can be ported. Gemini unverified. |
| Session resume / naming | Strongest for Claude; partial for Codex; generic CLIs not wired | Needs per-CLI session adapter audit/spec. |
| Claude usage meter | Claude-only by design | Provider/tool-specific usage adapters needed; not a simple port. |
| Launch diagnostics | Logs Claude/Codex paths only | Easy cleanup, not user-facing. |
| Agent docs shown in Info tab | Shows `CLAUDE.md` and `AGENTS.md` | Add tool-specific doc names if useful. |
| Onboarding / public docs | Mostly mention Claude/Codex | Update after deciding support level for OpenCode/Gemini. |
| Quick actions | Live-agent based, not Claude-only | No port needed; docs are stale. |
| Browser bridge | Environment variable for all agents | No port needed. |

## Findings

### 1. Sidebar agent state and workstream colors

Current behavior:

- `AgentHooks` only produces hook settings for `.claude`.
- `AgentHooks.settingsPathIfSupported(for: .codex)`, `.opencode`, and
  `.gemini` return `nil`.
- `TerminalContainerView.buildAgentCommand()` only writes hook settings when
  `AgentHooks` returns a supported path.
- The state model itself (`AgentState`, `AgentStateFiles`, `AgentStateStore`,
  and `WorkstreamStatusStyle`) is agent-neutral.

Source:

- `Sources/Models/AgentHooks.swift`
- `Sources/Views/TerminalContainerView.swift`
- `docs/superpowers/specs/2026-06-18-codex-workstream-status-hooks-design.md`

Porting notes:

- Codex supports lifecycle hooks, `--config key=value` overrides, and
  `--dangerously-bypass-hook-trust` for vetted one-off automation. This has
  already been designed in the Codex workstream status hooks spec.
- OpenCode docs mention plugins and custom tools, but this audit did not verify
  an OpenCode lifecycle hook equivalent for turn start / permission wait / turn
  stop.
- Gemini was not verified; local `gemini --help` hung in this environment and
  was terminated.

Follow-up spec:

- Already written: `2026-06-18-codex-workstream-status-hooks-design.md`.
- Later: OpenCode lifecycle-status adapter after verifying extension points.

### 2. Auto-rename branch and task description

Current behavior:

- The setting is exposed as "Auto-rename branch".
- `CodingCLI.supportsAutoRenameBranch` returns true for `.claude` and
  `.opencode`.
- The actual prompt is only added inside `buildClaudeAgentCommand(...)` via
  `--append-system-prompt`.
- Codex and OpenCode do not currently receive the rename instructions from
  `SystemPrompts.autoRenameBranchPrompt`.
- The settings warning says "Auto-rename branch is only available with Claude
  Code" when the selected CLI does not support it, which conflicts with
  `supportsAutoRenameBranch == true` for OpenCode.

Source:

- `Sources/Models/CommandBuilder.swift`
- `Sources/Models/SystemPrompts.swift`
- `Sources/Views/SettingsView.swift`

Porting notes:

- Codex has a `developer_instructions` config key for additional injected
  instructions, and CLI `--config key=value` one-off overrides. That is the
  likely adapter target.
- OpenCode supports inline config through `OPENCODE_CONFIG_CONTENT`, custom
  agent prompts, and a `--prompt` flag in the TUI command. A Dockyard-generated
  temporary config or generated agent prompt is likely the cleanest adapter.
- Gemini capability is unverified.

Follow-up spec:

- "Portable Dockyard system prompts": define a neutral prompt bundle with
  per-CLI injection mechanisms for:
  - restrict-to-worktree guidance
  - auto-rename branch
  - task description file update

### 3. Restrict writes to worktree

Current behavior:

- The setting is named "Allow writes outside worktree".
- For Claude, disabling outside writes injects
  `SystemPrompts.restrictToWorktreePrompt(...)` through
  `--append-system-prompt`.
- For Codex, disabling outside writes maps to `--sandbox workspace-write`; when
  enabled it maps to `--sandbox danger-full-access`.
- For OpenCode and Gemini, the generic command builder ignores this setting.

Source:

- `Sources/Models/CommandBuilder.swift`
- `Sources/Models/SystemPrompts.swift`
- `Sources/Views/SettingsView.swift`

Porting notes:

- Codex already has the strongest implementation here because it uses the CLI's
  sandbox mode rather than relying only on prompt obedience.
- Claude currently relies on instruction following. If stronger enforcement is
  needed, it would need an external sandbox or a Dockyard-side launcher policy.
- OpenCode has permission rules, including `external_directory`, `edit`, and
  `bash` controls. A generated `OPENCODE_CONFIG_CONTENT` policy could probably
  express the intended behavior, but it needs a separate design.
- Gemini was not verified.

Follow-up spec:

- "Per-CLI filesystem policy adapter": define what each setting promises and
  how close each CLI can get.

### 4. Agent Teams / multi-agent coordination

Current behavior:

- `CodingCLI.supportsAgentTeams` returns true only for `.claude`.
- `WorkstreamEnvironment` sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` only
  for Claude when the setting is enabled.
- `buildClaudeAgentCommand(...)` adds `--teammate-mode tmux` when tmux mode is
  enabled.
- The setting UI correctly disables Agent Teams outside Claude.

Source:

- `Sources/Models/CommandBuilder.swift`
- `Sources/Models/WorkstreamEnvironment.swift`
- `Sources/Views/SettingsView.swift`

Porting notes:

- Codex has a documented `features.multi_agent` setting, enabled by default in
  current docs. That is not the same product as Claude's teammate tmux mode.
- OpenCode has primary/subagent configuration, but that is not the same as
  Dockyard's current tmux workstream/team model.
- This should not be ported as a flag-for-flag clone. It needs a product design
  for how Dockyard should expose "agent teams" across CLIs.

Follow-up spec:

- "Portable agent teams": compare Claude teammate mode, Codex multi-agent tools,
  and OpenCode subagents, then define one Dockyard UX model.

### 5. Permission bypass

Current behavior:

- Claude gets `--dangerously-skip-permissions`.
- Codex gets `--ask-for-approval never` for interactive sessions.
- OpenCode and Gemini use `buildGenericAgentCommand(...)`, so the setting is
  ignored for them.

Source:

- `Sources/Models/CommandBuilder.swift`
- `Sources/Views/SettingsView.swift`

Porting notes:

- OpenCode local help exposes `opencode run --dangerously-skip-permissions` for
  run mode. The TUI command help did not show the same flag, so the desired
  interactive behavior needs verification.
- OpenCode also supports config-level permissions and defaults to permissive
  behavior unless configured otherwise, so the setting semantics need careful
  wording.
- Gemini was not verified.

Follow-up spec:

- Include in the per-CLI filesystem/permission policy adapter spec.

### 6. Session resume and session naming

Current behavior:

- Claude uses the workstream UUID as the session id:
  - resume: `--resume <workstream-id>`
  - fresh: `--session-id <workstream-id>`
- Claude may also receive `--name <workstream-name>` when the installed version
  supports it.
- Codex uses `codex resume --last` before falling back to a fresh command.
- Codex does not currently get a deterministic workstream session id/name from
  Dockyard.
- OpenCode and Gemini use `buildGenericAgentCommand(...)`, so Dockyard does not
  wire their session-resume features.

Source:

- `Sources/Models/CommandBuilder.swift`
- `Sources/Views/SettingsView.swift`
- local `codex resume --help`
- local `opencode --help`

Porting notes:

- Codex resume is likely scoped by working directory, but Dockyard should not
  rely on `--last` forever if the CLI can target a more stable session id/name.
- OpenCode local help exposes `--continue`, `--session`, `--fork`, and
  `--title`.
- Gemini was not verified.

Follow-up spec:

- "Per-workstream session identity": define deterministic resume semantics for
  each CLI and how Dockyard should recover if the session no longer exists.

### 7. Claude usage meter

Current behavior:

- The sidebar usage meter is a Claude-specific feature.
- `ClaudeUsageParser` reads local Claude Code transcripts under
  `~/.claude/projects`.
- `ClaudeUsageProbe` runs `claude -p '/usage' --output-format json`.
- Settings expose a "Claude usage plan" picker.

Source:

- `Sources/Models/ClaudeUsage.swift`
- `Sources/Models/ClaudeUsageProbe.swift`
- `Sources/Models/ClaudeUsageStore.swift`
- `Sources/Views/SidebarStatusStrip.swift`
- `Sources/Views/SettingsView.swift`

Porting notes:

- This should become a provider/tool usage abstraction only if the other tools
  expose comparable local usage data.
- OpenCode local help exposes `opencode stats`, but this audit did not inspect
  output shape or account/window semantics.
- Codex public docs include usage/account surfaces, but this audit did not find
  a direct local equivalent to Claude Code's `/usage` command.

Follow-up spec:

- "Usage meters by agent": decide whether Dockyard should show:
  - Claude-only meter with clearer labeling
  - per-agent usage cards
  - no usage meter unless a reliable adapter exists

### 8. Launch diagnostics and detailed logs

Current behavior:

- `LaunchLogEntry.ToolPaths` stores `agentCLI`, `claude`, `codex`, `tmux`, and
  `ffRun`.
- It does not store OpenCode or Gemini paths even though both can be selected as
  Coding CLIs.

Source:

- `Sources/Models/LaunchLogger.swift`
- `Sources/Views/TerminalContainerView.swift`

Porting notes:

- This is not user-facing feature parity, but it makes debugging non-Claude
  agents weaker.
- Easy cleanup: add `opencode` and `gemini` to the log schema in a backward
  compatible way.

Follow-up spec:

- Not necessary unless grouped into a small "agent adapter cleanup" task.

### 9. Agent documentation shown in the Info tab

Current behavior:

- The Info tab loads `README.md`, `CLAUDE.md`, and `AGENTS.md`.
- It does not include tool-specific docs such as `GEMINI.md`.
- `AGENTS.md` is shared by Codex and OpenCode, so this is not purely
  Claude-only, but the file list is Claude-biased.

Source:

- `Sources/Views/WorkstreamInfoView.swift`

Porting notes:

- Add more standard agent instruction filenames only if the app wants the Info
  tab to be a general "agent instructions" surface.

Follow-up spec:

- Optional documentation UX cleanup.

### 10. Onboarding and public docs

Current behavior:

- Onboarding says "Install Claude Code or Codex to use the Coding Agent."
- The onboarding prerequisite list shows Claude Code and Codex, but not
  OpenCode or Gemini.
- README copy also highlights Claude Code and Codex while runtime settings list
  OpenCode and Gemini.

Source:

- `Sources/Views/OnboardingView.swift`
- `README.md`

Porting notes:

- This is mostly a product-support messaging issue, not a technical adapter.
- Do not advertise OpenCode/Gemini as first-class until their command adapter,
  permissions, session resume, and prompt injection behavior are clear.

Follow-up spec:

- Include in the small "agent adapter cleanup" task after the technical parity
  decisions are made.

## Not actually Claude-only

These showed up in the search but should not be treated as porting work.

### Quick actions

Commit and Create PR quick actions are sent as text to the live Agent tab:

```swift
surfaceCache.sendText(to: agentID, text: prompt + "\r")
```

That means they use whichever Coding CLI is active in the workstream. Older
docs still describe deleted per-CLI quick-action subprocess commands, so the
docs are stale, but the runtime behavior is not Claude-only.

Source:

- `Sources/Views/TerminalContainerView.swift`
- `Sources/Models/QuickActionRunner.swift`
- stale doc: `docs/sidebar-and-toolbar.md`

### Browser bridge

`DOCKYARD_BROWSER_STATE_FILE` is injected into every workstream environment
through `WorkstreamEnvironment.variables(...)`. Older task-tracking text calls
it "Claude Integration", but the current data path is agent-neutral.

Source:

- `Sources/Models/WorkstreamEnvironment.swift`
- `Sources/Models/BrowserBridge.swift`

### Tmux persistence wrapper

The outer tmux wrapper is applied to the built command for any selected CLI
when tmux mode is enabled. The Claude-specific part is only
`--teammate-mode tmux`, not the tmux process wrapper itself.

Source:

- `Sources/Models/CommandBuilder.swift`
- `Sources/Models/TmuxSession.swift`

## Recommended spec order

1. Codex workstream status hooks.
   - Already designed.
   - Highest value because it unlocks PR #24's sidebar state model for Codex.

2. Portable Dockyard system prompts.
   - Covers auto-rename branch, task description, and restrict-to-worktree
     prompt guidance.
   - Should start with Codex, then OpenCode.

3. Per-CLI permission and filesystem policy adapter.
   - Clarifies the exact semantics of "Bypass permission prompts" and "Allow
     writes outside worktree" for every CLI.

4. Per-workstream session identity.
   - Makes resume behavior deterministic instead of tool-specific luck.

5. Agent teams portability study.
   - Larger product design; do after core single-agent parity.

6. Usage meter strategy.
   - Decide whether this remains Claude-only or becomes a pluggable usage
     surface.

7. Small adapter cleanup.
   - Launch log paths for OpenCode/Gemini.
   - Info tab doc filename list.
   - Onboarding and README support matrix.
   - Stale docs in `docs/sidebar-and-toolbar.md`.

## External sources checked

- Codex hooks: <https://developers.openai.com/codex/hooks>
- Codex CLI/config options: <https://developers.openai.com/codex/cli/reference>
- Codex config reference: <https://developers.openai.com/codex/config-reference>
- OpenCode config: <https://opencode.ai/docs/config>
- OpenCode CLI: <https://opencode.ai/docs/cli>
- OpenCode agents: <https://opencode.ai/docs/agents>
- OpenCode permissions: <https://opencode.ai/docs/permissions>

## Verification notes

- Local `codex --help` and `codex resume --help` were checked successfully.
- Local `opencode --help` and `opencode run --help` were checked successfully.
- Local `gemini --help` hung without output and was terminated. Gemini support
  remains unverified in this audit.
