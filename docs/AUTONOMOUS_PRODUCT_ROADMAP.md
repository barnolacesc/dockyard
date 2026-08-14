# Dockyard Autonomous Product Roadmap

Last reconciled: 2026-08-14 against `origin/main` at
`ceeea0811d385396f497632469a705b184a13953`.

This is the product-direction record for autonomous development. GitHub issues
and pull requests remain the execution record. `TODO.md` is source material,
not an automatically trusted backlog.

The final **Live reconciliation** section is canonical. Earlier dated sections
are retained as an audit trail and can contain statuses superseded by a later
reconciliation.

## Evidence and limits

- Repository: `barnolacesc/dockyard`; native SwiftUI/AppKit macOS app using
  Ghostty, git worktrees, tmux, WKWebView, Monaco and XcodeGen.
- Open implementation issues at reconciliation: #40, #41, #43, #54 and #69.
- Open pull requests: implementation PR #70 and release-please #63. PR #63
  must not be changed, merged or released without Cesc's explicit approval.
- Latest published release: v0.2.1. `main` CI, Release and CodeQL were green at
  `33b3fdb`; the most recent scheduled CodeQL run was also green.
- GitHub Projects v2 was not reviewed. The current token has `repo` and
  `workflow`, but lacks `read:project`; the API returned
  `INSUFFICIENT_SCOPES`. Project status must not be inferred.
- `project.yml` is canonical. Generated Xcode project files are not roadmap
  evidence and must never be edited directly.
- Native Swift/macOS changes require green `macos-15` GitHub CI. Linux checks
  are useful static evidence only.

## Product principles

1. A normal restart must preserve project, workstream, terminal and tmux state.
2. Worktree and command boundaries are safety boundaries; cleanup and bypass
   behavior must be explicit, contained and reversible where possible.
3. Claude Code, Codex and OpenCode behavior must be described only to the
   extent proven by code and tests.
4. Native keyboard, focus, contrast, accessibility and motion quality are
   product behavior, not polish deferred indefinitely.
5. All user-facing strings ship in English, Catalan, German, Spanish and
   Swedish.
6. Signing, notarization, updates and distribution require evidence across the
   entire release chain; merging code is not publishing a release.

## Required track coverage

| Track | Current evidence | Next decision or item |
| --- | --- | --- |
| Worktree lifecycle, persistence, cleanup and merged-PR review | Creation, remove-without-delete, purge, orphan listing and clean prune exist. Force-removal and branch deletion have tests. `TODO.md` still requests merged-PR-aware cleanup. | R2 adds classification only; any destructive bulk action remains approval-gated. |
| Tmux, terminal and session resilience | Dedicated `dockyard` socket, deterministic sessions, `new-session -A`, respawn hooks, tab snapshots and tests already implemented app-restart persistence. A later termination cleanup regressed that behavior by killing the dedicated server on quit. This does not preserve sessions across a macOS reboot. | R1 / issue #69 restores the original app-restart contract; system-reboot persistence is separate future scope. |
| Coding CLI compatibility and agent/subagent status | Claude Code and Codex have specialized command builders. OpenCode and Gemini are detected and launched through the generic builder; README only claims Claude/Codex. Claude/Codex hooks report main-agent state. | R3 defines and tests the honest OpenCode contract. Issue #54 needs discovery before implementation. |
| macOS lifecycle, performance, accessibility, contrast and keyboard behavior | AppDelegate tests, shortcut references, accessibility labels and five localizations exist. Issue #41 reports slow quit; #40 reports sidebar contrast failure. | Profile #41 on macOS; R4 fixes #40 with contrast and visual evidence. |
| Script guardrails, worktree containment, privacy and entitlements | Script fingerprint approval, re-approval on change, command quoting tests, worktree prompts, `SECURITY.md`, `PRIVACY.md`, `THREAT_MODEL.md` and minimal entitlement docs exist. | Continue boundary tests before new execution features. Changes to approval, bypass, privacy or entitlements stop at PR for Cesc. |
| Setup/run/teardown reliability and port detection | Fallback configs, environment injection, `dy-run`, process-tree port detection, FSEvents state and focused tests exist. | R5 adds bounded recovery coverage for stale run-state. |
| Embedded browser/editor quality and safe boundaries | WKWebView browser state and Monaco editor exist; browser JavaScript policy and navigation have tests. Full Chrome/CDP control was explicitly deferred in `TODO.md`. | Review bridge/navigation boundaries before any bidirectional automation. |
| Onboarding, tours, What's New, docs and localization | Onboarding, Getting Started, What's New and five app localizations exist. Two tour follow-ups remain in `TODO.md`. | R6 adds the smaller workspace-tabs tour with all locale coverage. |
| CI, Ghostty, dependencies, release/update integrity and distribution | macOS build/test CI, CodeQL, Dependabot, pinned actions, Ghostty compatibility workflow, checksums, Sparkle and Homebrew paths exist. Release-please #63 is pending. | Release/update mutations remain approval-gated; verify feed and published artifacts separately from CI. |

## Now

### R1 — Restore tmux persistence across Dockyard app restarts

- Status: **In review, blocked on fork CI approval (PR #70)** on
  `fix/preserve-tmux-restarts`; issue #69.
- Classification: **regression fix, not a new persistence feature**. The
  original tmux architecture already used deterministic session names and
  `new-session -A` to reconnect after relaunch. The later
  `applicationWillTerminate` cleanup introduced on 2026-03-31 broke that
  contract by killing the entire dedicated tmux server.
- User outcome: quitting and reopening Dockyard once again reconnects to
  existing Coding Agent tmux sessions instead of destroying them.
- Boundary: this covers **Dockyard app quit/relaunch only**. A macOS shutdown or
  reboot terminates tmux itself, so system-reboot persistence is not
  implemented or claimed by this item.
- Success signal: `AppDelegate` has no normal-termination callback that runs
  `tmux -L dockyard kill-server`; explicit per-workstream archive/purge cleanup
  remains unchanged.
- macOS impact: app termination and relaunch behavior.
- Persistence/security impact: removes an unconditional destructive process
  launch and restores the previously implemented tmux persistence boundary.
- Scope: remove global tmux-server cleanup from app termination and remove the
  now-unreachable helper. No session naming, archive or purge changes.
- Dependencies: none.
- Risk: low, reversible reliability fix. Native CI is mandatory.
- Acceptance criteria:
  1. Normal termination does not register a tmux cleanup callback.
  2. `killWorkstreamSessions` remains available for explicit cleanup.
  3. XCTest regression, full build and full tests pass on GitHub macOS CI.
- Required tests: focused `AppDelegateTests`, repository secret/diff checks,
  GitHub `CI / build-and-test`; CodeQL checks as configured.
- Sources: README Tmux Mode, repository `AGENTS.md`, `TmuxSession.swift`,
  `DockyardApp.swift`, issue #69.

### R4 — Guarantee readable sidebar workstream states

- Status: **Ready**, after R1. Source issue #40.
- User outcome: primary and secondary workstream text remains readable while
  default, hovered, selected, waiting, working or invalid.
- Success signal: a deterministic state/token matrix has no selected-state
  pairing that uses muted status text over an accent selection background.
- macOS impact: native SwiftUI sidebar appearance and accessibility.
- Persistence/security impact: none.
- Scope: sidebar workstream foreground/background tokens only; no redesign.
- Dependencies: reliable screenshot or manual macOS evidence for light/dark and
  at least one custom accent color.
- Risk: low visual behavior, but do not merge without native visual evidence.
- Acceptance criteria: unit-tested state resolution, all five locales
  unaffected or updated if strings change, VoiceOver labels preserved, and
  before/after macOS evidence attached.
- Required tests: `WorkstreamStatusStyleTests`, full macOS build/test, visual
  matrix.
- Sources: issue #40 and `ProjectSidebar.swift`.

### P1 — Reproduce and profile slow app termination

- Status: **Needs evidence**, not Ready. Source issue #41.
- User outcome: Dockyard closes smoothly without a 1–3 second freeze.
- Success signal: Instruments or signposts identify the blocking path and a
  repeatable macOS measurement establishes baseline and target.
- macOS impact: application lifecycle and animation responsiveness.
- Persistence/security impact: cleanup must not trade speed for lost terminal,
  worktree or persisted state.
- Scope: profiling and minimal instrumentation first; no speculative cleanup
  deletion.
- Dependencies: reproducible macOS run with representative terminals,
  browsers and workstreams.
- Risk: medium because lifecycle teardown crosses Ghostty, WebKit and process
  ownership.
- Acceptance criteria: recorded baseline, attributed main-thread blocker and a
  bounded follow-up item.
- Required tests: existing AppDelegate/terminal tests plus native profiling.
- Sources: issue #41.

## Next

### R2 — Classify merged-PR worktrees without deleting them

- Status: **Ready**.
- User outcome: users can see which retained worktrees belong to merged PRs
  before deciding what to remove.
- Success signal: pure classification identifies clean, dirty, ahead,
  merged-PR and unknown states without running removal or branch-delete
  commands.
- macOS impact: project overview status only.
- Persistence/security impact: read-only first slice; destructive follow-up is
  explicitly excluded and approval-gated.
- Scope: model/classifier, tests and a non-destructive label.
- Dependencies: existing GitHub PR metadata and worktree state.
- Risk: low if strictly read-only.
- Acceptance criteria: classification tests cover dirty, ahead and unavailable
  PR data; no cleanup command is added.
- Required tests: focused classifier/UI model tests and full macOS CI.
- Sources: unchecked merged-PR bulk action in `TODO.md`.

### R3 — Define and prove the OpenCode compatibility contract

- Status: **Ready**.
- User outcome: an OpenCode user knows exactly what launch, tmux and status
  behavior Dockyard supports.
- Success signal: command-builder tests cover OpenCode launch paths and docs
  distinguish generic launch support from session resume, hooks, bypass mode
  and subagent reporting.
- macOS impact: Coding Agent selection and launch.
- Persistence/security impact: no new permissions; unsupported bypass behavior
  must remain disabled and clearly described.
- Scope: tests and documentation first; no new OpenCode command flags without
  upstream CLI evidence.
- Dependencies: current `CodingCLI.opencode` generic builder.
- Risk: low.
- Acceptance criteria: tested direct and tmux-wrapped commands, accurate README
  support matrix, no claim of hooks/resume/bypass unless implemented.
- Required tests: `CommandBuilderTests`, `AgentHooksTests`, full macOS CI.
- Sources: hard product direction, `CommandBuilder.swift`, `SettingsView.swift`.

### R5 — Reject stale run-state after a run process exits

- Status: **Ready**.
- User outcome: an embedded browser does not keep targeting a dead dev server
  after an abnormal run-script exit or app restart.
- Success signal: stale/mismatched run-state JSON is ignored and tested without
  deleting valid state from another workstream.
- macOS impact: Environment tab and embedded browser targeting.
- Persistence/security impact: validates cache identity and lifecycle; no
  command execution changes.
- Scope: port/run-state validation and focused tests.
- Dependencies: current `dy-run` state schema and PortDetector behavior.
- Risk: low to medium.
- Acceptance criteria: fixtures cover valid, stale, malformed and mismatched
  workstream state; current valid port detection remains green.
- Required tests: `PortDetectionTests`, full macOS CI.
- Sources: setup/run/teardown and port-detection required track.

### R6 — Add the workspace-tabs showcase tour

- Status: **Ready**, lower priority.
- User outcome: new users discover terminal, browser and editor tabs plus tab
  cycling without reading the full shortcut list.
- Success signal: a passive, dismissible tour covers Cmd+T/B/O and cycling,
  with no automatic command execution.
- macOS impact: onboarding/tour overlay and keyboard discoverability.
- Persistence/security impact: tour completion state only; no scripts launched.
- Scope: one `TourFlow`, What's New link if release version is known, and five
  localizations.
- Dependencies: current Tour framework and release-please version when adding
  What's New.
- Risk: low visual behavior; requires native visual evidence.
- Acceptance criteria: tour controller tests, all locale keys, keyboard
  navigation and VoiceOver labels.
- Required tests: tour/localization tests, full macOS CI and screenshots.
- Sources: unchecked workspace-tabs tour in `TODO.md`.

## Later

### D1 — Design truthful main-agent and subagent status reporting

- Status: **Discovery**, not Ready. Source issue #54.
- User outcome: a workstream shows which agent or subagent needs attention
  without false-positive “working” state.
- Success signal: documented event semantics and fixtures for Claude Code,
  Codex and OpenCode before UI implementation.
- macOS impact: sidebar/status surfaces.
- Persistence/security impact: state files and hooks must be per-workstream,
  bounded and resilient to stale writers.
- Scope: vendor capability matrix and normalized state model first.
- Dependencies: stable, documented events from each CLI.
- Risk: medium; external CLI output is untrusted.
- Acceptance criteria: no unsupported CLI claim, stale-event policy, privacy
  review and test fixtures.
- Required tests: parser/state-store concurrency and stale-data tests.

### D2 — Audit embedded browser/editor integration boundaries

- Status: **Discovery**, not Ready.
- User outcome: browser and editor integrations remain useful without exposing
  arbitrary native capabilities to loaded content.
- Success signal: threat-model addendum maps every WKScriptMessage handler,
  navigation decision and file bridge to validation tests.
- macOS impact: WKWebView browser and Monaco editor.
- Persistence/security impact: high security relevance; no entitlement or
  JavaScript-policy expansion in the audit.
- Scope: review and tests, not CDP or Chrome-extension implementation.
- Dependencies: current browser/editor bridge inventory.
- Risk: medium.
- Acceptance criteria: complete bridge inventory and negative tests for
  out-of-scope paths/origins.
- Required tests: `BrowserViewTests`, editor bridge tests and CodeQL.

### D3 — Release and distribution integrity verification

- Status: **Approval-gated**, not Ready for autonomous merge/release.
- User outcome: signed/notarized downloads, Sparkle feed and Homebrew cask all
  point to the same verified version.
- Success signal: published artifacts, checksums, signatures, appcast and cask
  are cross-checked after an explicitly approved release.
- macOS impact: installation and updates.
- Persistence/security impact: executable update trust boundary.
- Scope: verification checklist before any release mutation.
- Dependencies: Cesc approval, credentials, release-please #63 and live feed.
- Risk: high.
- Acceptance criteria: explicit approval and end-to-end artifact evidence.
- Required tests: release workflow, signature/notarization verification,
  Sparkle feed and Homebrew install checks.

## Parked

- **Issue #43, hide update terminal window:** parked behind the update-execution
  approval gate. The repository includes a source-update path and Sparkle; the
  exact visible terminal source must be reproduced before changing executable
  launch behavior.
- **External Chrome/CDP control:** `TODO.md` records that it does not unlock the
  Claude-in-Chrome extension. No work without a new bounded product case and
  security design.
- **Website DNS/Pages, fork detachment and Poblenou branding:** external
  coordination or product decisions, not autonomous code work.
- **Release-please #63:** never merge or publish without explicit Cesc
  approval.

## Reconciliation notes

- `TODO.md` says VRA phase 2 is incomplete, but `SECURITY.md`, `PRIVACY.md`,
  `THREAT_MODEL.md`, `docs/vendor-risk.md` and
  `docs/install-from-source.md` are present. Treat the TODO checkbox as stale;
  audit content accuracy before claiming the security review complete.
- README's selectable-CLI claim is intentionally narrower than the enum in
  code. OpenCode/Gemini generic launch presence is not evidence for full
  session, hook, bypass or status compatibility.
- A checked TODO or merged PR is not release evidence. Roadmap items become
  complete only after merge and after any required native or release
  verification.

## Run log

- **2026-07-25:** bootstrapped roadmap from code, `TODO.md`, docs, issues, PRs,
  releases and CI. Projects v2 unavailable due missing `read:project`.
  Selected R1 / issue #69 and opened PR #70 from
  `fix/preserve-tmux-restarts`. GitHub created CI and CodeQL runs with
  `action_required`; the automation account lacks the upstream admin right
  needed to approve fork workflows. Native evidence and merge remain pending;
  no release action requested.
- **2026-07-26:** reconciled `origin/main`, open issues/PRs, latest release and
  current workflow state; no overlapping implementation work was selected.
  Reviewed PR #70 against R1 acceptance criteria and confirmed explicit
  per-workstream cleanup remains intact. Retried approval of both fork workflow
  runs through the GitHub API; each returned `403 Must have admin rights`.
  Native macOS CI and CodeQL therefore remain blocked pending an upstream
  repository administrator's approval. Reclassified R1 and PR #70 as a
  regression fix restoring the original app-restart contract, and explicitly
  excluded macOS reboot persistence from its claims. No merge or release action
  was taken.
- **2026-07-27:** fetched unchanged `origin/main` at `33b3fdb`, reconciled the
  same open implementation issues and PRs, and reviewed PR #70's complete diff.
  `git diff --check` passed, the PR remains Git-mergeable, and the regression
  test plus explicit per-workstream cleanup boundary remain intact. At PR head
  `18227f7`, both GitHub workflows were still `action_required`; approving run
  `30193549215` (macOS CI) and run `30193549211` (CodeQL) again returned
  `403 Must have admin rights`. A dry-run upstream branch push also returned
  `403`, confirming the automation account cannot move the same commits onto an
  upstream branch to bypass fork approval. R1 remains the only selected item.
  Cesc must approve the fork workflow runs before native CI can execute; no
  merge or release action was taken.

## Live reconciliation — 2026-08-09 09:30 CEST

This section supersedes older statuses above while roadmap-bearing PRs await
review. `origin/main` is `99b68df`; R1 / PR #70 is merged. Implementation PRs
#71–#105 (odd numbers) are **awaiting Cesc review** and have successful macOS
`build-and-test` checks at their current heads. Their implementation paths and
behaviors were compared before selecting this run. Release-please PR #63
remains approval-gated, and v0.2.1 remains the latest published release.
GitHub Projects v2 returned `INSUFFICIENT_SCOPES` because the token lacks
`read:project`, so no Project status is inferred.

### R14 — Keep editor navigation inside the worktree

- Status: **Awaiting Cesc review in PR #107** for issue #106 on
  `fix/contain-editor-workspace-paths`; the PR must not be auto-merged.
- User outcome and success signal: repository files discovered through the
  embedded editor tree cannot read or overwrite a path outside the selected
  worktree. Tests cover ordinary descendants, a symlinked worktree root,
  absolute and traversal-shaped paths, same-prefix siblings, contained
  symlinks, escaping file/directory symlinks and lazy child loading.
- Impact and scope: add one canonical workspace-relative resolver, filter
  escaping entries from `FileNode`, and use the resolver for implicit editor
  loads, ordinary saves and the Save As starting directory. The explicit
  `NSSavePanel` destination remains user-directed and unrestricted. No command
  execution, entitlement, persisted-data migration, localization or generated
  project behavior changes.
- Risk and required evidence: medium file-access boundary. Focused
  `WorkspaceFileAccessTests`, full macOS build/test, CodeQL, diff and secret
  checks are required. The Linux automation container has neither Swift/Xcode
  nor XcodeGen, so GitHub `macos-15` CI is the mandatory native evidence.
- Native evidence: GitHub macOS CI run `31301763342` passed XcodeGen, the native
  build and the full XCTest suite at head `76dee1f`. CodeQL run `31301763333`
  completed successfully; its Swift analysis was skipped by workflow
  configuration. The final roadmap-only head must also remain green.
- Independence: PR #89 changes only bundled Monaco resource-scheme validation;
  R14 changes workspace tree/file I/O and can merge in either order.

### Independent Ready queue while R14 awaits review

- **R15 — Preserve current cache state during legacy migration:** when legacy
  and canonical run-state or tmux cache entries both exist, never delete the
  canonical destination before a fallible move. `CacheMigration` and focused
  tests only; migration behavior is approval-gated and must stop at a tested
  PR for Cesc.
- **R16 — Contain automatic development-environment activation:** automatic
  run wrapping and PATH injection must not source or prepend `venv`, `.venv`
  or `node_modules/.bin` paths that resolve outside the selected project.
  `RunLauncher`, `WorkstreamEnvironment` and focused tests only; this command
  boundary is approval-gated and must stop at a tested PR for Cesc.
- **R17 — Protect tmux diagnostic state:** create the Dockyard tmux cache
  directory and stderr log with private permissions before shell redirection,
  without changing tmux commands, session persistence or cleanup behavior.
  `TmuxSession` and focused tests only; full macOS CI is required.

- **2026-08-09 09:30 CEST:** reconciled `origin/main`, `TODO.md`, issues,
  releases, every open PR path and current check at its head. Projects v2
  remained unavailable without `read:project`. Selected independent R14,
  created issue #106 and opened PR #107 from current `origin/main`; no prior PR
  was modified or commented on, and no merge or release action was taken.

## Live reconciliation — 2026-08-09 16:30 CEST

This section supersedes all earlier item statuses. Cesc reviewed and merged
autonomous PRs #71–#77 directly, then PR #108 merged reviewed PRs #79–#107 as
a tested merge train. `origin/main` is now `2a92c7e`; its macOS CI, CodeQL and
Release workflows succeeded. The prior Ready items for sidebar contrast,
merged-PR classification, OpenCode compatibility, stale run-state rejection,
workspace-tabs tour, persistence/privacy hardening and path containment are
therefore shipped on `main`, not awaiting review.

Only release-please PR #63 remains open. It is approval-gated, has
`action_required` fork workflow runs and must not be merged or published by an
autonomous cycle. The latest published release remains v0.2.1. Open issues at
selection time were #41, #43 and #54; bounded issue #109 records this cycle's
implementation. GitHub Projects v2 again returned `INSUFFICIENT_SCOPES`
because the token has `repo` and `workflow` but lacks `read:project`; no
Project item or status is inferred.

### R15 — Preserve current cache state during legacy migration

- Status: **Awaiting Cesc review in PR #110** on
  `fix/preserve-cache-migration-destination` for issue #109; native CI evidence
  is pending. This is persisted-data migration behavior, so the implementation
  must stop at a tested PR for Cesc's review.
- User outcome: launching Dockyard cannot replace a current run-state directory
  or tmux configuration merely because a legacy cache entry also exists.
- Success signal: legacy entries move only when their canonical destinations
  are absent; when both exist, canonical bytes remain unchanged and legacy
  data remains available for inspection.
- macOS impact: startup cache migration only; no UI or localization changes.
- Persistence/security impact: removes destructive conflict handling from a
  one-time persisted-data migration. No schema, command, entitlement, cleanup
  or release behavior changes.
- Scope: `CacheMigration` plus focused `CacheMigrationTests`.
- Risk: medium because startup migration touches retained terminal/run state.
- Acceptance criteria:
  1. Existing canonical run-state and tmux entries are never removed or
     replaced by conflicting legacy entries.
  2. Legacy entries still migrate when the canonical destination is absent.
  3. Conflicting legacy entries remain in place rather than being silently
     discarded.
  4. Focused tests and full GitHub macOS build/test pass.
- Required evidence: focused XCTest, full macOS CI, CodeQL as configured,
  `git diff --check`, localization parity and secret scan.
- Native evidence: at implementation head `02e0be9`, macOS CI run
  `31319027774` passed localization parity, XcodeGen, the native build and the
  full XCTest suite including `CacheMigrationTests`. CodeQL run `31319027777`
  passed Actions and JavaScript analysis; Swift analysis was skipped by the
  repository workflow configuration. The final roadmap-only head must also
  remain green.
- Independence: release-please #63 changes version/changelog material only;
  R15 changes cache migration and tests, so neither depends on the other.

### Independent Ready queue while R15 awaits review

- **R16 — Contain automatic development-environment activation:** automatic
  run wrapping and PATH injection must not source or prepend `venv`, `.venv`
  or `node_modules/.bin` paths that resolve outside the selected project.
  `RunLauncher`, `WorkstreamEnvironment` and focused tests only; this command
  boundary is approval-gated and must stop at a tested PR for Cesc.
- **R17 — Protect tmux diagnostic state:** create the Dockyard tmux cache
  directory and stderr log with private permissions before shell redirection,
  without changing tmux commands, session persistence or cleanup behavior.
  `TmuxSession` and focused tests only; full macOS CI is required.
- **R18 — Add the passive power-features tour:** expose existing shortcut
  hints, usage meters, tmux persistence and archive semantics without launching
  commands or changing persisted workstreams. One `TourFlow`, controller tests,
  five localizations and native visual/accessibility evidence; source is the
  remaining unchecked tour item in `TODO.md`.

- **2026-08-09 16:30 CEST:** reconciled the reviewed merge train, current
  `origin/main`, `TODO.md`, open issues/PRs, releases, CI and Projects v2 scope.
  Selected R15 / issue #109 as the highest-priority independent Ready item from
  a fresh `origin/main` worktree. No release, merge or older-PR comment was
  performed.

## Live reconciliation — 2026-08-14 12:00 CEST: Orca-informed direction

This section supersedes every earlier status and ordering. It is a product
reconfiguration prompted by an evidence-led comparison with
[stablyai/orca](https://github.com/stablyai/orca), an MIT-licensed ADE. It is
not a plan to copy its implementation or to make unverified feature claims.

### Current repository and delivery state

- `origin/main` is `ceeea08`. The local checkout formerly used by automation
  was stale and is not roadmap evidence.
- Open non-release implementation issues: #41 (slow quit), #43 (visible update
  terminal) and #54 (subagent status). The persistence, editor and
  localization hardening issues #112, #114, #116, #118, #120, #122 and #124
  each have an open implementation PR (#113, #115, #117, #119, #121, #123 and
  #125 respectively); do not create overlapping work until those land or are
  reviewed.
- Release-please #63 remains approval-gated and is excluded from autonomous
  work. GitHub Projects v2 was not reviewed: the available token does not have
  `read:project`.
- Dockyard already has the difficult local foundation: isolated worktrees,
  native Ghostty terminals, terminal splits, tmux restoration, browser/editor,
  worktree-aware port detection, GitHub PR state, agent attention notifications,
  Claude and Codex usage meters, and a selectable Claude/Codex/OpenCode/Gemini
  CLI surface. It is intentionally a native macOS product, not a cross-platform
  rewrite.

### Orca capability audit and Dockyard response

| Orca capability, verified 2026-08-14 | Dockyard truth today | Product response |
| --- | --- | --- |
| Any CLI agent, with a large preconfigured catalog | Four CLI choices are surfaced; Claude and Codex have specialized launch/resume/permission paths, while OpenCode and Gemini are generic launch paths. | **Now:** define a versioned agent-adapter contract. Add adapters only with command, resume, state and safety tests; never add a logo catalogue that lies. |
| Fan one task into several isolated worktrees and compare results | Workstreams already create isolated worktrees, but task fan-out and comparison are not first-class. | **Next:** add a bounded “parallel task batch” planner that creates workstreams from an explicit task and records parent/batch metadata. No auto-merge or automatic winner selection. |
| Live main-agent/subagent attention, unread state and follow-ups | Main Claude/Codex state is persisted; issue #54 asks for subagent status. There is no normalized timeline/inbox. | **Now:** build a read-only normalized activity model and an attention inbox before trying to orchestrate subagents. |
| Inline diff annotations, batched feedback, CI/conflict/review flow | PR links and Quick Actions exist; there is no local diff-review/comment loop. | **Now:** add read-only diff review first, then opt-in queued comments sent as a normal agent prompt. Do not mutate GitHub review state silently. |
| Chromium Design Mode: inspect a clicked element and send DOM/CSS/screenshot to agent | Dockyard has a safe WKWebView browser-state export; bidirectional browser automation is explicitly deferred. | **Next:** design-mode spike limited to the local preview origin, explicit user gesture, bounded DOM payload and redacted screenshot. It is a browser security boundary, not a WKWebView script-message free-for-all. |
| Native GitHub/Linear task intake, boards and PR approval | GitHub repository/PR information exists through `gh`; no issue intake, board or Linear integration. | **Next:** GitHub issue-to-workstream intake with an explicit task preview. Park Linear until Cesc chooses it; do not add SaaS auth by vibes. |
| SSH worktrees, remote runtimes, reconnect and port forwarding | Local macOS worktrees only. | **Later:** remote runtime protocol discovery and threat model. This is a new credentials, host-key, filesystem and port-forwarding trust boundary; no implementation without Cesc approval. |
| iOS/Android companion to monitor, notify and steer work | Dockyard has local notifications only. | **Later:** local-first companion architecture exploration after the activity protocol is stable. Do not build a cloud relay as a side quest. |
| CLI/API for agents to control the ADE (`worktree`, `snapshot`, `click`, `fill`) | Dockyard has an `ff` launcher, but not an automation control plane. | **Later:** capability-scoped automation CLI only after worktree and browser security design. No arbitrary app-control API. |
| Search across worktrees/files/agents/commands/context; rich previews; split-anything | File tree/editor/docs, terminal splits and Markdown rendering exist; there is no universal command/search palette or broad preview system. | **Later:** keyboard-first command palette and indexed local search; retain native performance/accessibility as the constraint. |
| Account hot-switching and rate-limit reset tracking | Claude/Codex usage measurement exists; switching identities does not. | **Parked:** usage visibility is valuable; account switching touches credential stores and must wait for an explicit privacy/security design. |
| Computer Use | Not present. | **Parked:** too broad and too dangerous without a specific local workflow and permission model. |

Orca also ships desktop, mobile and headless Linux-server variants. These are
useful reference points, not evidence that Dockyard should abandon its native
macOS focus. Orca's public feature list and release history explicitly show
that terminal resynchronization, remote ownership and mobile delivery are
high-churn reliability areas; Dockyard should earn those features in vertical
slices instead of speed-running into an incident report.

### Product principles after the comparison

1. Dockyard becomes the **trustworthy macOS control plane for a small fleet of
   coding agents**, not a generic Electron clone.
2. Build observation and review before delegation and remote control: users
   must be able to understand, interrupt and correct agent work.
3. “Any CLI” means a tested adapter contract with declared capabilities, not a
   bare terminal command masquerading as full support.
4. Every external-action surface keeps a human confirmation boundary: worktree
   deletion, PR approval/merge, remote access, credentials, browser automation
   and account changes never become autonomous defaults.
5. Preserve the existing commitments: native performance, keyboard-first flow,
   five localizations, privacy/no telemetry, minimum entitlements and
   durable-restart correctness.

## Now

### R23 — Agent capability contract and truthful status foundation

- Status: **Ready for discovery slice**, independent of open hardening PRs.
- User outcome: a user knows, per selected CLI, whether Dockyard can launch,
  resume, report main-agent state, report subagents, use tmux and enable a
  permission mode.
- Success signal: a declarative capability matrix drives Settings/help UI and
  tests prevent unsupported controls from being offered.
- Scope: extract existing Claude/Codex/OpenCode/Gemini knowledge into a tested
  adapter/capability model; document state-source semantics. No new provider,
  credential, permission or CLI flag.
- Risk: medium because incorrect state claims erode trust; all event payloads
  remain untrusted and bounded.
- Acceptance: command-builder and state fixtures cover every visible claim;
  all user-facing strings are localized; macOS CI passes.
- Sources: issue #54, `CommandBuilder.swift`, `AgentStateStore.swift`, Orca
  agent-catalog comparison.

### R24 — Attention inbox and activity timeline (read-only)

- Status: **Ready after R23’s state vocabulary is merged**.
- User outcome: unanswered agent questions, completions and stale workstreams
  are visible in one keyboard-navigable inbox, with per-workstream context.
- Success signal: deterministic fixtures distinguish working, waiting, idle,
  stale and unknown; marking a local item read never changes a terminal,
  agent, GitHub object or worktree.
- Scope: local event store, sidebar count, inbox/list UI and deep links to the
  relevant workstream. Explicitly excludes subagent launch/control.
- Risk: low to medium persistence/UI work; no agent transcript upload.
- Acceptance: retention/decay rules, restart recovery, VoiceOver labels,
  five locales and macOS visual evidence.

### R25 — Local diff review and queued feedback

- Status: **Ready for a read-only spike after R24**.
- User outcome: review a workstream’s diff, add line comments and send a
  deliberate batch back to its chosen agent without losing context.
- Success signal: diff is generated strictly for the resolved worktree; queued
  comments are visibly editable, persisted locally and injected only after an
  explicit “Send to agent” action.
- Scope: local git diff, line anchors, comment queue and a prompt handoff.
  Excludes GitHub PR review submission, auto-approval, auto-merge and arbitrary
  repository paths.
- Risk: medium file/path and prompt-injection boundary.
- Acceptance: worktree-containment tests, adversarial diff fixtures, restart
  recovery and macOS interaction evidence. Stop at a PR for Cesc if the
  interaction can cause command execution beyond typing into the agent.

### R26 — Release and lifecycle reliability remain non-negotiable

- Status: **Concurrent maintenance track**.
- User outcome: the agent-control surface does not trade away app quit
  performance, tmux restoration, state privacy, localization integrity or
  update safety.
- Success signal: the currently open R16–R22 hardening PRs receive review and
  their macOS CI stays green; issue #41 is profiled before changing lifecycle
  cleanup; #43 remains approval-gated.
- Scope: no overlap with existing PRs. Treat regressions as higher priority
  than the roadmap items above.

## Next

### R27 — Parallel task batches with comparison, never auto-selection

- User outcome: fan an explicitly chosen task into two to five isolated
  workstreams, label them as a batch and compare diff/test/agent status before
  the human chooses what to keep.
- Success signal: batch metadata survives restart; each child has unique branch
  and worktree; deleting one child follows existing explicit cleanup rules.
- Scope: creation wizard, batch model and overview; no automatic prompts beyond
  the user-approved template, no winner/merge algorithm.
- Dependencies: R23/R24 and existing worktree safety tests.
- Risk: medium destructive-lifecycle adjacency; requires macOS CI and visual
  evidence.

### R28 — Design Mode for local previews, behind a capability gate

- User outcome: select an element in the local dev preview and attach a cropped
  screenshot plus bounded DOM/CSS context to an agent follow-up.
- Success signal: only a user click on a permitted local preview origin can
  generate context; payload size/redaction are tested and the agent sees a
  preview before send.
- Scope: research/design then an isolated opt-in implementation. No arbitrary
  JavaScript bridge, Chrome extension, remote origin or Computer Use.
- Dependencies: browser bridge threat-model addendum and R25’s explicit prompt
  handoff.
- Risk: high security boundary; always stop at a tested PR for Cesc.

### R29 — GitHub issue intake to workstream

- User outcome: choose a GitHub issue, inspect the proposed task context and
  create one contained workstream with a traceable source link.
- Success signal: no task starts without confirmation; issue text is rendered
  as untrusted data; missing `gh`/auth state fails clearly.
- Scope: GitHub only. Linear/boards are deliberately excluded until a product
  and authorization decision exists.
- Dependencies: existing GitHub integration and R23 task context model.
- Risk: medium external-data/prompt-injection boundary; no GitHub mutation.

## Later

- **R30 — Command palette and local search:** fast keyboard discovery over
  workstreams, files, agents, commands and docs; local index only, with clear
  cache/privacy policy.
- **R31 — Rich local previews:** images, PDFs and repository documents inside
  contained workstreams, following a file-size/type and path-validation design.
- **R32 — Remote runtime discovery:** SSH worktrees, reconnection and port
  forwarding only after a separate threat model covers host keys, credentials,
  filesystem roots, forwarding and disconnect recovery. Requires Cesc approval
  before implementation.
- **R33 — Mobile companion discovery:** read-only, local-first monitoring and
  notification architecture after the desktop activity protocol is proven.

## Parked

- Account switching/hot-swapping for Claude or Codex: credential-store and
  privacy work; usage tracking already gives useful value without it.
- Linear integration, project-board access and SaaS synchronization: no current
  user decision or `read:project` scope.
- Computer Use and a general ADE automation API: unacceptable privilege surface
  without a narrow, approved workflow.
- Cross-platform rewrite: explicitly out of scope. Dockyard’s native macOS
  integration is its differentiator.
- Release-please #63, notarization, Sparkle/appcast and Homebrew publication:
  still require explicit Cesc approval.

### Reconciliation record

- Compared Dockyard source, `TODO.md`, open issues/PRs and the public Orca
  README, product site and current v1.4.182 release notes on 2026-08-14.
- Orca observations are product inspiration only; each adoption item names a
  Dockyard-specific boundary, measurable signal and evidence requirement.
- The autonomous queue must select only one small, non-overlapping Ready item
  per run, update this roadmap in the implementation PR, and never mark an
  item complete before merge and required macOS evidence.
