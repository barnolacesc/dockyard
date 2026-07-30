# Dockyard Autonomous Product Roadmap

Last reconciled: 2026-07-27 against `origin/main` at
`33b3fdb6c227d8b633f3163e22aba93046046d84`.

This is the product-direction record for autonomous development. GitHub issues
and pull requests remain the execution record. `TODO.md` is source material,
not an automatically trusted backlog.

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

- Status: **In review (PR #73)** on
  `feat/merged-pr-worktree-status`; issue #72. GitHub `macos-15` build and
  XCTest passed at `a80a496`; awaiting Cesc's native project-overview
  verification. Never auto-merge.
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
- Sources: issue #72 and the unchecked merged-PR bulk action in `TODO.md`.
- Next independent Ready item after this PR: R3, the OpenCode compatibility
  contract. It does not depend on this worktree-status slice or sidebar PR #71.

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
