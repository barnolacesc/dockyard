# Dockyard Autonomous Product Roadmap

Last reconciled: 2026-08-02 against `origin/main` at
`99b68dfb91afbb80c2a48f0c20b3f0aa3cfd4f9e`.

This is the product-direction record for autonomous development. GitHub issues
and pull requests remain the execution record. `TODO.md` is source material,
not an automatically trusted backlog.

## Evidence and limits

- Repository: `barnolacesc/dockyard`; native SwiftUI/AppKit macOS app using
  Ghostty, git worktrees, tmux, WKWebView, Monaco and XcodeGen.
- Open implementation issues at reconciliation: #40, #41, #43, #54, #72,
  #74, #76, #78, #80, #82 and #84.
- Open implementation pull requests: #71, #73, #75, #77, #79, #81, #83 and
  #85. They are independent, have green macOS CI on their final heads except
  #71's still-missing native run and this run's new #85 pending CI, and await
  Cesc's review. PR #85 does not modify or stack on earlier pending work.
- Release-please PR #63 remains open. It must not be changed, merged or
  released without Cesc's explicit approval.
- Latest published release: v0.2.1. `main` is at `99b68df`; recent autonomous
  PRs with native changes have green macOS CI where noted in their PR evidence.
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
| Worktree lifecycle, persistence, cleanup and merged-PR review | Creation, remove-without-delete, purge, orphan listing and clean prune exist. Force-removal and branch deletion have tests. `TODO.md` still requests merged-PR-aware cleanup. | R2 / PR #73 adds read-only classification; any destructive bulk action remains approval-gated. |
| Tmux, terminal and session resilience | Dedicated `dockyard` socket, deterministic sessions, `new-session -A`, respawn hooks and tab snapshots preserve normal app restarts. R1 / PR #70 removed the regressing global server kill. This does not preserve sessions across a macOS reboot. | R8 / PR #83 isolates malformed tab snapshots; system-reboot persistence remains separate scope. |
| Coding CLI compatibility and agent/subagent status | Claude Code and Codex have specialized command builders. OpenCode and Gemini are detected and launched through the generic builder; README only claims Claude/Codex. Claude/Codex hooks report main-agent state. | R3 defines and tests the honest OpenCode contract. Issue #54 needs discovery before implementation. |
| macOS lifecycle, performance, accessibility, contrast and keyboard behavior | AppDelegate tests, shortcut references, accessibility labels and five localizations exist. Issue #41 reports slow quit; #40 reports sidebar contrast failure. | R4 / PR #71 fixes #40; profile #41 on macOS before changing lifecycle behavior. |
| Script guardrails, worktree containment, privacy and entitlements | Script fingerprint approval, re-approval on change, command quoting tests, worktree prompts, `SECURITY.md`, `PRIVACY.md`, `THREAT_MODEL.md` and minimal entitlement docs exist. | R7 / PR #79 repairs state-directory modes. Changes to approval, bypass, privacy or entitlements stop at PR for Cesc. |
| Setup/run/teardown reliability and port detection | Fallback configs, environment injection, `dy-run`, process-tree port detection, FSEvents state and focused tests exist. | R5 / PR #77 rejects stale and mismatched run-state. |
| Embedded browser/editor quality and safe boundaries | WKWebView browser state and Monaco editor exist; browser JavaScript policy and navigation have tests. Full Chrome/CDP control was explicitly deferred in `TODO.md`. | Review bridge/navigation boundaries before any bidirectional automation. |
| Onboarding, tours, What's New, docs and localization | Onboarding, Getting Started, What's New and five app localizations exist. Two tour follow-ups remain in `TODO.md`. | R6 / PR #81 adds the workspace-tabs tour; R10 adds locale-key parity. |
| CI, Ghostty, dependencies, release/update integrity and distribution | macOS build/test CI, CodeQL, Dependabot, pinned actions, Ghostty compatibility workflow, checksums, Sparkle and Homebrew paths exist. Release-please #63 is pending. | R10 adds deterministic localization-key parity; release/update mutations remain approval-gated. |

## Now

### R1 — Restore tmux persistence across Dockyard app restarts

- Status: **Complete on `main`** via PR #70; issue #69 closed.
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

- Status: **Awaiting Cesc review** in PR #71. Source issue #40. Native CI and
  visual review remain required before merge.
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

- Status: **Awaiting Cesc review** in PR #73 with green macOS CI; issue #72.
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

- Status: **Awaiting Cesc review** in PR #75 with green macOS CI; issue #74.
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

- Status: **Awaiting Cesc review** in PR #77 with green macOS CI; issue #76.
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

- Status: **Awaiting Cesc review** in PR #81 with green macOS CI; issue #80.
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

### R7 — Enforce private state-directory permissions

- Status: **Awaiting Cesc review** in PR #79 with green macOS CI; issue #78.
- User outcome: agent and run-state metadata remains private to the current
  macOS account even when a watcher created the state directory first.
- Success signal: every atomic state write repairs its parent directory to
  `0700`, keeps the destination file at `0600`, and leaves no temporary file.
- macOS impact: local filesystem permissions for helper/app state.
- Persistence/security impact: privacy hardening only; no state schema,
  command, worktree, entitlement or telemetry change.
- Scope: `FilePersistence` and focused tests.
- Dependencies: none; its implementation paths do not overlap this run.
- Risk: low and reversible, but privacy-related; stop at a tested PR for Cesc.
- Acceptance criteria: first and replacement writes enforce private modes,
  replacement content is correct, and no temporary file remains.
- Required tests: `FilePersistenceTests` and full macOS CI.
- Sources: issue #78 and PR #79.

### R8 — Isolate malformed workspace-tab snapshots

- Status: **Awaiting Cesc review** in PR #83 with green macOS CI; issue #82.
- User outcome: one malformed or old workstream snapshot does not erase the
  restored tabs for every other workstream.
- Success signal: snapshot decoding skips only the invalid entry and preserves
  all valid workstream entries without changing their schema.
- macOS impact: workspace restoration after app restart or upgrade.
- Persistence/security impact: recovery-only behavior; no destructive migration.
- Scope: `WorkspaceTabSnapshotStore` plus focused tests; no terminal lifecycle
  or UI redesign.
- Dependencies: none; no other open PR touches its implementation paths.
- Risk: low and reversible.
- Acceptance criteria: mixed valid/invalid fixtures preserve valid entries;
  save and remove preserve unrelated valid entries; load deletes no snapshot.
- Required tests: `WorkspaceTabStateTests` and full macOS CI.
- Sources: issue #82 and PR #83.

### R9 — Recover the agent-state watcher after directory replacement

- Status: **In review (PR #85), awaiting Cesc review**; issue #84. Native
  macOS CI is mandatory on the final head.
- User outcome: agent attention indicators resume updating if the cache/state
  directory is cleared or replaced while Dockyard is running.
- Success signal: a delete/rename event recreates and reattaches the directory
  watcher, then observes a new valid state file without an app restart.
- macOS impact: DispatchSource lifecycle and sidebar status freshness.
- Persistence/security impact: observes cache state only; no new writer or CLI
  capability.
- Scope: `AgentStateStore` watcher recovery plus focused tests.
- Dependencies: none; no open PR touches `AgentStateStore.swift` or
  `AgentStateTests.swift`.
- Risk: low to medium due filesystem-event timing.
- Acceptance criteria: deterministic recovery test, old watcher cancellation
  closes its descriptor, and existing decay/stale-PID behavior remains green.
- Required tests: `AgentStateTests` and full macOS CI.
- Sources: issue #84 and the existing `.delete`/`.rename` event mask without
  reattachment.

### R10 — Enforce localization-key parity in CI

- Status: **Ready**.
- User outcome: a feature cannot merge with a missing Catalan, German, Spanish
  or Swedish string that silently falls back to English.
- Success signal: a deterministic check compares every supported locale key
  set with English and fails on missing or extra keys.
- macOS impact: localization release integrity; no runtime behavior.
- Persistence/security impact: none.
- Scope: one static checker, tests and CI invocation; no translation changes.
- Dependencies: none; it does not edit locale content.
- Risk: low.
- Acceptance criteria: fixtures cover parity, missing, extra, comments and
  escaped strings; the current five locales pass unchanged.
- Required tests: checker tests, current-tree validation and CI.
- Sources: localization invariant in `AGENTS.md`; no current parity gate.

### R11 — Enforce Monaco resource containment by path component

- Status: **Ready**.
- User outcome: embedded editor resource requests cannot escape the bundled
  Monaco directory through traversal or a sibling path with the same prefix.
- Success signal: a pure containment check accepts descendants and rejects
  traversal plus prefix-collision siblings.
- macOS impact: embedded Monaco resource loading only.
- Persistence/security impact: tightens a read-only bundle boundary.
- Scope: containment helper and negative tests; no bridge capability changes.
- Dependencies: none; paths do not overlap open implementation PRs.
- Risk: low security hardening; stop at a tested PR for Cesc review.
- Acceptance criteria: valid bundled assets load, invalid paths fail closed,
  and macOS CI is green.
- Required tests: focused Monaco scheme-handler tests and full macOS CI.
- Sources: `MonacoResourceSchemeHandler` and D2 boundary inventory.

### R12 — Make browser-state cache files private

- Status: **Ready**.
- User outcome: captured URLs, titles and console messages are not readable by
  other local users through permissive cache modes.
- Success signal: browser-state directories are `0700` and files are `0600`,
  including repair of existing permissive paths.
- macOS impact: browser-state persistence only.
- Persistence/security impact: privacy hardening; schema remains unchanged.
- Scope: `BrowserBridge` permissions and focused tests; no new messages,
  origins or entitlements.
- Dependencies: none; implementation paths are separate from PR #79.
- Risk: low to medium privacy boundary; stop at a tested PR for Cesc review.
- Acceptance criteria: read/write/clear behavior stays green and permissions
  are repaired deterministically on macOS.
- Required tests: `BrowserViewTests` and full macOS CI.
- Sources: browser/editor boundary track and `BrowserBridge.swift`.

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
- **2026-08-02 (16:30 CEST):** reconciled `origin/main` at `99b68df`, open
  issues, release state, and the changed paths and checks for implementation
  PRs #71, #73, #75, #77, #79, #81 and #83. All remain independent and await
  Cesc's review; none was modified or commented on. Projects v2 remains
  unavailable because the token lacks `read:project`. Selected R9, opened
  issue #84 and PR #85, and added watcher recovery after the agent-state
  directory is deleted or renamed. A focused test removes the directory and
  proves a new valid snapshot is observed without manual refresh. Linux static
  checks passed; native macOS CI is mandatory on the final head. No merge or
  release action was taken. R10 is the next independent Ready item.
