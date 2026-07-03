# Sidebar and toolbar — reference

This document describes how the workstream sidebar row and the workspace's top-right toolbar are wired: where their state comes from, how often it refreshes, and what each visual signal means.

It is meant as a reference for contributors. For the agent-state indicator redesign (planned replacement of the title/bell heuristics), see `superpowers/specs/2026-05-17-agent-state-indicator-design.md`.

## Sidebar workstream row

`WorkstreamRow` in `Sources/Views/ProjectSidebar.swift` composes a single row from eight pieces of state. Each piece is cached on `AppEnvironment` (`Sources/Models/Environment.swift`) and refreshed on its own cadence.

### Inputs

| Field | Source | Refresh trigger |
| --- | --- | --- |
| `name` | `Workstream.name` (UserDefaults via `ProjectStore`) | persisted; no refresh |
| `branchName` | `AppEnvironment.branchNameCache[path]` | `refreshPathValidity` (15s timer) |
| `isPathValid` | `AppEnvironment.pathValidityCache[path]` — `FileManager.fileExists` | `refreshPathValidity` (15s timer) |
| `taskDescription` | `AppEnvironment.taskDescriptionCache[path]` — reads `<worktree>/.dockyard-state/description` | `refreshPathValidity` (15s timer) |
| `prTitle`, `prState` | `AppEnvironment.githubBranchPRCache["<dir>\|<branch>"]` | `refreshAllBranchPRs` (throttled to 30s) |
| `hasActivePort` | `AppEnvironment.activePortCache: Set<UUID>` — reads `RunStateStore.loadValidated(for:).detectedPorts` (written by the `dy-run` helper) | `refreshPathValidity` (15s timer) |
| `isActive` | `WorkstreamActivityTracker.activeWorkstreamIDs` — terminal title changed within the last 5s | `.terminalTitleChanged` notification |
| `needsAttention` | `WorkstreamActivityTracker.needsAttentionIDs` — terminal BEL rang | `.terminalNeedsAttention` notification (cleared on focus / typing / mouse) |

`isActive` and `needsAttention` are the two unreliable signals the agent-state spec replaces.

### Headline

The `headline` (`ProjectSidebar.swift:902-906`) is the first non-nil of:

1. PR title
2. Task description
3. Workstream name

`taskDescription` is whatever's in `<worktree>/.dockyard-state/description`, written by the Coding Agent when the "Auto-rename branch" system prompt is active (see `Sources/Models/SystemPrompts.swift`). It lets the row reflect what the agent thinks the workstream is about, rather than the random `adjective-noun` from `NameGenerator`.

### Subtitle

The `subtitle` (`ProjectSidebar.swift:912-921`) follows these rules:

- If the headline is "rich" (PR title or task description), the subtitle is the **branch name**.
- Else if the branch name differs from the workstream name, the subtitle is the branch name.
- Else there is no subtitle.

### Visual signals

| Element | Meaning |
| --- | --- |
| Pulsing **green** dot (left, 12pt slot) | Terminal title flickered in the last 5 seconds — proxy for "agent active." Unreliable; redesign in progress. |
| Pulsing **accent** dot (left) | Terminal BEL rang — proxy for "needs attention." Unreliable; cleared by focus/typing/mouse. |
| Static **gray** dot (left) | Idle. |
| **Orange triangle** (left) | Worktree path missing on disk (`isPathValid == false`). Overrides all agent signals. |
| Tiny **green** dot (right of headline) | `dy-run` reports the workstream's run script is listening on a TCP port. |
| **Strikethrough** headline | Worktree path is invalid. |
| **Accent** headline + **accent** subtitle | `needsAttention` is set — overrides every other color. |
| **Purple** subtitle + `arrow.triangle.merge` icon | PR is in state `MERGED` — work is done, candidate for archive. |
| **Tertiary** subtitle | Default: no PR, or PR is OPEN/CLOSED. |

## Top-right toolbar

`TerminalContainerView.swift:837-863` adds a `ToolbarItemGroup(placement: .primaryAction)` whenever a workstream tab is the active tab. Two items appear there.

### GitHub icon button

`Button { NSWorkspace.shared.open(githubURL) }` where `githubURL` is built by `AppEnvironment.githubURL(for:branch:)` from the `origin` remote (origin is preferred over upstream so forks open against the user's own fork). Opens `https://github.com/<owner>/<repo>/tree/<branch>` in the system browser. Hidden when the repo has no GitHub remote.

### `GitHubActionMenu` — the split-button that morphs

A SwiftUI `Menu` whose primary action label changes based on repo state, with secondary actions tucked into the chevron. Defined in `TerminalContainerView.swift:1413-1611`.

#### Primary-action decision tree

(`primaryAction` computed property, line 1438-1463)

| PR state | Worktree state | Primary label |
| --- | --- | --- |
| `MERGED` | any | _(hidden)_ |
| `OPEN` | uncommitted changes | **Commit** |
| `OPEN` | clean + unpushed + has remote | **Push** |
| `OPEN` | clean (and not unpushed) | **Open #N** _(opens the PR in browser)_ |
| _no PR_ | has remote + has branch commits | **Create PR** |
| _no PR_ | uncommitted changes | **Commit** |
| _no PR_ | clean + unpushed + has remote | **Push** |
| none of the above | | _(hidden)_ |

#### Secondary menu

`secondaryActions` (line 1466-1485) lists every action that currently applies, then removes whichever is already shown as primary. So if Commit is primary, the chevron menu might contain Push, Create PR, Open #N, Close PR.

#### What each action does (`QuickActionRunner.swift`)

| Action | Implementation |
| --- | --- |
| **Commit** | Runs the configured Coding CLI with the prompt: _"Stage and commit all changes in the working tree with a good commit message based on the changes. Do not push."_ |
| **Push** | `GitOperations.pushCurrentBranch(at:)` → `git push -u origin HEAD`. No LLM. |
| **Create PR** | Runs the Coding CLI with the prompt: _"Create a pull request for the current changes. Write a clear title and description based on what we've been working on."_ |
| **Close PR** | `gh pr close <branch> --comment 'Closed from Dockyard'`. No LLM. |
| **Open #N** | Pure browser link: `NSWorkspace.shared.open(pr.url)`. |

LLM quick actions are sent to the live Agent tab, so they run under whatever permission mode the current Coding Agent session is using:

- **Commit:** inserts the commit prompt into the Agent tab.
- **Create PR:** inserts the pull-request prompt into the Agent tab.
- **Close PR:** still runs `gh pr close`; it does not use the Coding Agent.

#### Disabled states (`disabledReason`, line 1505-1518)

- LLM actions (Commit, Create PR) require the Coding CLI to be installed.
- Close PR requires `gh` to be installed.

#### Visual states during execution

- Idle → action label + SF Symbol icon
- Running → `ProgressView()` (mini)
- Succeeded → label with a green `checkmark.circle.fill`
- Failed → label with a red `xmark.circle.fill`

Both terminal states auto-revert to idle after 3 seconds (`QuickActionRunner.scheduleDismiss`).

#### Post-action refresh

`startWorkspace` wires `quickActionRunner.onSuccess` (`TerminalContainerView.swift:1218-1228`):

1. Always refresh worktree state immediately (so the menu re-evaluates).
2. If the action was `closePR`: clear the cached branch PR.
3. If the action was `createPR` or `closePR`: call `refreshGitHubInfo` so the new PR state appears.

## Refresh cadence — the whole picture

A single 15-second timer in `ContentView.swift:468-474` drives the sidebar's freshness:

```
Timer.publish(every: 15)
  ├─ refreshAllRepoInfo(projects)      // 10s for recent (<5 min), 60s otherwise
  ├─ refreshPathValidity(projects)     // paths, branches, task descs, ports, github remote
  ├─ refreshAllBranchPRs(projects)     // throttled to 30s; one `gh pr list` per project, limit 100
  ├─ fetchOrigin(projects)             // throttled to 2 min per project; `git fetch`
  └─ syncWorkstreamNamesFromBranches   // if user renamed a branch outside Dockyard
```

`refreshWorktreeState(for:projectDirectory:)` is separate and fresher — throttled to 5s per worktree path, called on:

- `startWorkspace` (workspace first opens)
- Workspace `onAppear`
- Active tab change (`onChange(of: activeTab)`)
- `.terminalActivity` notification (any keystroke in any terminal of the workspace)
- After any successful quick action

`refreshGitHubInfo(for:branch:)` is on-demand only — called from `WorkstreamInfoView.onAppear`, `ProjectOverviewView`, and after a successful Create/Close PR.

### Consequence

The sidebar's PR badge can be up to **30 seconds stale** in the typical case, and up to **45 seconds** worst case (waiting for the next 15s timer tick that also crosses the 30s throttle).

The active workstream's toolbar menu is much fresher — worktree state refreshes every 5 seconds and immediately after any action, so the primary-action label keeps up with what the user is doing.
