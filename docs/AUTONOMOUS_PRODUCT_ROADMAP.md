# Dockyard Autonomous Product Roadmap

Last reconciled: 2026-08-20 against `origin/main` at
`fce9d0f61ee8b673ea1f09f27cb82e7d0245b5fb`.

This is the product-direction record for autonomous development. GitHub issues
and pull requests remain the execution record. `TODO.md` is source material,
not an automatically trusted backlog.

The **Current autonomous queue** is canonical. Dated **Live reconciliation**
sections are retained as an audit trail and can contain superseded statuses.

## Current autonomous queue — 2026-08-20 09:30 CEST

`origin/main` is `fce9d0f`; its latest macOS CI, CodeQL and Release workflows
are green. R36–R38 are merged. PR #140 (R39) is clean, green and **awaiting
Cesc review**. PRs #117 and #126 are green at their heads but conflict with
current `main`; they also remain awaiting Cesc review and are not modified or
stacked on here. Release-please PR #63 remains approval-gated and must not be
merged or published autonomously. The latest published release is v0.2.1.

GitHub Projects v2 returned `INSUFFICIENT_SCOPES`: the automation token has
`repo` and `workflow` but lacks `read:project`. No Project item or status is
inferred. Open product issues at selection were #41, #43, #54 and #116; issue
#141 records this run.

### R39 — Aggregate active Claude Code subagents into workstream status

- Status: **Awaiting Cesc review in PR #140** on
  `feat/claude-subagent-status-r39` for issue #54. Required macOS CI and
  configured CodeQL checks are green at head `eeb0988`.
- Independence: R39 changes agent hooks, state aggregation, capability docs and
  focused Swift tests. R40 changes only deterministic build verification and
  macOS CI, so either implementation can merge first.

### R40 — Verify bundled helper integrity in macOS CI

- Status: **Awaiting Cesc review in PR #142** on
  `ci/verify-bundled-helpers-r40` for issue #141. Required native
  implementation CI is green; never auto-merge this PR.
- User outcome: a green native build cannot omit the `dy-run` or
  `dy-agent-state` helper and silently break environment launch or agent-status
  integration at runtime.
- Success signal: the post-build CI verifier accepts the actual Debug app only
  when both canonical `Contents/Helpers` entries are regular executable files.
- macOS impact: verifies the native app bundle produced on `macos-15`; no UI,
  accessibility, localization, shortcut or runtime behavior changes.
- Persistence/security impact: read-only artifact inspection. It does not
  execute helpers or change commands, state, signing, entitlements, updates or
  releases.
- Scope: a standalone Python verifier, deterministic fixture tests, one
  post-build CI invocation and roadmap evidence. `project.yml` and generated
  Xcode project files are unchanged.
- Dependencies: none. Open PRs #117, #126, #140 and #63 own disjoint
  implementation paths and behavior.
- Risk: low and reversible CI hardening; green GitHub macOS CI is mandatory.
- Acceptance criteria:
  1. A complete app-bundle fixture passes.
  2. Missing, non-executable and symlinked helper fixtures fail precisely.
  3. CI checks the actual Debug bundle after `./scripts/dev.sh build`.
  4. Localization parity, XcodeGen, native build and full XCTest remain green.
- Required evidence: focused Python tests, localization scripts,
  `git diff --check`, added-line secret scan, full macOS `build-and-test` and
  configured CodeQL.
- Native evidence: at head `a6f318c`, macOS CI run `32344974032` passed
  localization checks, XcodeGen, the native build, the actual bundled-helper
  verification and the full XCTest suite. CodeQL run `32344974025` passed its
  configured Actions and JavaScript analyses; Swift analysis was skipped by
  the repository workflow configuration. The final roadmap-only head must also
  remain green. Linux is not native macOS evidence.
- Sources: issue #141, PR #142, `project.yml` helper post-build phases,
  `.github/workflows/ci.yml` and the R40 Ready item recorded by PR #140.

### Independent Ready queue while R39 and R40 await review

- **R41 — Bound run-state cache reads before decoding.** User outcome: a
  malformed cache entry cannot make browser retargeting allocate unbounded
  memory or cross a symlink boundary. Success signal: only bounded regular
  files decode, while valid state still retargets. macOS/persistence impact:
  read-only run-state validation; no schema, deletion, migration or command
  change. Scope: `RunStateStore` and focused fixtures. Dependencies: none and
  no open PR owns these paths. Risk: low; focused XCTest and full macOS CI.
- **R42 — Build a read-only GitHub issue task preview.** User outcome: future
  issue intake can show exactly what would be handed to an agent before any
  worktree or prompt exists. Success signal: title, number, URL and bounded
  body text normalize deterministically as untrusted input. macOS/persistence
  impact: pure model/parser only. Scope: no GitHub mutation, credential,
  command, agent launch or worktree creation. Dependencies: none. Risk: low;
  parser fixtures and full macOS CI.
- **R43 — Bound startup tool-detection probes.** User outcome: a broken or
  hostile CLI cannot hang Dockyard startup indefinitely or emit unbounded
  version/help output. Success signal: process-double tests prove timeout,
  termination, output cap and normal version detection. macOS/security impact:
  narrows existing local executable probes without changing CLI launch
  commands or permissions. Scope: `ToolStatus` command runner and focused
  tests. Dependencies: none and disjoint from #140's agent-state paths. Risk:
  medium command-boundary change; stop at a tested PR for Cesc and require full
  macOS CI.

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

### R20 — Keep watcher-created state directories private

- Status: **Awaiting Cesc review in PR #121** on
  `fix/private-watcher-state-directories` for issue #120; do not auto-merge.
  Required native implementation CI is green.
- User outcome: Dockyard does not leave run-state or agent-state watcher
  directories readable or traversable by other local users because of a
  permissive process umask or an existing permissive directory.
- Success signal: both watchers create and repair their state directories as
  `0700` before attaching filesystem observers, including agent-state watcher
  recovery, without replacing retained state files.
- macOS impact: local filesystem watcher setup only; no UI, accessibility,
  localization or visual behavior changes.
- Persistence/security impact: narrows permissions on existing cache
  directories without changing schemas, state writers, worktree behavior,
  command execution, entitlements or cleanup.
- Scope: `PortDetector`, `AgentStateStore`, focused watcher/state tests and
  roadmap evidence only.
- Dependencies: none. Open PRs #113, #115, #117 and #119 change environment
  activation, tmux diagnostics, tour/sidebar content and editor writes;
  release-please #63 changes release metadata. R20's implementation paths and
  behavior are independent and can merge in either order.
- Risk: low and reversible local permission hardening. Native CI is mandatory.
- Acceptance criteria:
  1. Missing run-state and agent-state directories are created as `0700`.
  2. Existing `0755` directories are repaired to `0700` without replacing
     retained files.
  3. Agent-state directory replacement recovery re-establishes `0700` before
     watching the replacement.
  4. Existing run-state and agent-state observation behavior remains green.
  5. Full GitHub macOS build/test passes.
- Required evidence: focused XCTest, full `macos-15` CI, CodeQL as configured,
  localization parity, diff and secret checks.
- Evidence so far: localization parser tests and 418-key parity passed locally;
  `git diff --check` and the added-line secret scan passed. The Linux host has
  no Swift, Xcode or XcodeGen, so GitHub macOS CI is the mandatory native
  build/test evidence. At head `9718872`, macOS CI run `31574879569` passed
  localization parity, XcodeGen, the native build and the full XCTest suite;
  CodeQL run `31574879598` passed its configured analyses. The final
  roadmap-only head must also remain green. Roadmap head `f40847a` passed
  localization parity and XcodeGen before the third-party `setup-bun` action
  failed with a transient `TypeError: fetch failed` in run `31575222849`; no
  repository build or test ran on that attempt. The automation token received
  `403` when requesting a failed-job rerun, so a subsequent evidence-only head
  is required rather than treating that infrastructure failure as product
  evidence.
- Sources: issue #120, `PortDetector`, `AgentStateStore`, and private-state
  invariants already enforced by `FilePersistence`.

### Independent Ready queue while R16–R20 await review

GitHub Projects v2 remains unavailable: the token has `repo` and `workflow`
but lacks `read:project`, and the API returned `INSUFFICIENT_SCOPES`. No
Project item or status is inferred. `origin/main` is `ceeea08`; its latest
push CI, CodeQL and Release workflows are green. The latest published release
remains v0.2.1.

- **R21 — Validate localized macOS privacy prompts in CI:** extend the
  deterministic localization checker to verify `InfoPlist.strings` key parity
  across all five locales. This is a read-only release-integrity guard; it must
  not add usage descriptions, entitlements or privacy claims.
- **R22 — Validate localization bundle membership in CI:** add a deterministic
  manifest check proving `project.yml` includes `Localizable.strings` and
  `InfoPlist.strings` for every supported locale. Scope is a standalone script,
  focused Python tests and one CI invocation; it must not regenerate or edit
  the Xcode project, localization values, usage descriptions or entitlements.

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

### R19 — Contain close-tab editor saves within the worktree

- Status: **Awaiting Cesc review in PR #119** for issue #118 on
  `fix/contain-close-tab-editor-saves`; do not auto-merge. Required native
  implementation CI is green.
- User outcome: choosing Save while closing a dirty editor tab cannot write
  outside the selected worktree, including when restored or malformed editor
  state contains an absolute path, traversal, same-prefix sibling or escaping
  symlink.
- Success signal: ordinary and close-tab saves share one
  `WorkspaceFileAccess` writer; contained relative paths save successfully,
  while unsafe paths raise a file-write permission error and leave external
  bytes unchanged.
- macOS impact: the existing native Save / Don't Save / Cancel close alert is
  unchanged; only its Save destination resolution changes.
- Persistence/security impact: narrows an editor file-write boundary. Save As
  remains explicitly user-directed, and no persisted schema or cleanup
  behavior changes.
- Scope: `WorkspaceFileAccess`, ordinary editor save reuse, close-tab save and
  focused tests. No command execution, worktree, entitlement, localization or
  release changes.
- Dependencies: none; implementation paths do not overlap open PRs #113, #115,
  #117 or release-please #63.
- Risk: medium because this is a file-write boundary; stop at a tested PR for
  Cesc and do not auto-merge.
- Acceptance criteria:
  1. A contained relative path writes the requested bytes.
  2. Absolute, traversal, same-prefix and escaping-symlink paths fail before
     writing outside the worktree.
  3. External files remain unchanged for every rejected case.
  4. Existing editor and workspace file-access behavior remains green.
  5. Full GitHub macOS build/test passes.
- Evidence: localization parser tests and 418-key parity passed locally;
  `git diff --check` and the added-line secret scan passed. At head `41e8f97`,
  macOS CI run `31502647742` passed localization parity, XcodeGen, the native
  build and full XCTest. CodeQL run `31502647712` passed its Actions and
  JavaScript analyses; Swift analysis was skipped by the PR workflow. The
  final roadmap-only head must also remain green. Local `prek`/SwiftFormat was
  unavailable because those executables are not installed on the Linux host.
- Sources: issue #118, `TerminalContainerView.confirmCloseEditor`,
  `EditorView.saveFile` and `WorkspaceFileAccess`.

### Independent Ready queue after R19

GitHub Projects v2 remains unavailable: the token has `repo` and `workflow`
but lacks `read:project`, and the API returned `INSUFFICIENT_SCOPES`. No
Project item or status is inferred.

- **R20 — Keep watcher-created state directories private:** create and repair
  run-state and agent-state watcher directories as `0700` before attaching
  filesystem observers. Scope is `PortDetector`, `AgentStateStore` and focused
  tests; state schemas, writers and watcher recovery remain unchanged.
- **R21 — Validate localized macOS privacy prompts in CI:** extend the
  deterministic localization checker to verify `InfoPlist.strings` key parity
  across all five locales. This is a read-only release-integrity guard; it must
  not add usage descriptions, entitlements or privacy claims.

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

## Live reconciliation — 2026-08-16 09:30 CEST

This section supersedes every earlier status. `origin/main` is `ceeea08`; its
latest macOS CI, CodeQL and Release workflows succeeded. v0.2.1 remains the
latest published release. GitHub Projects v2 was queried and returned
`INSUFFICIENT_SCOPES`: the automation token has `repo` and `workflow` but not
`read:project`, so no Project item or status is inferred.

Implementation PRs #113 (R16), #115 (R17), #117 (R18), #119 (R19), #121
(R20), #123 (R21), #125 (R22), #128 (R23) and #131 (R34) are clean,
Git-mergeable, green on macOS `build-and-test`, and **awaiting Cesc review**.
Roadmap-only PR #126 is also clean and green. Their changed paths, behaviors
and dependencies were compared before this run; none is modified, stacked on
or duplicated here. Release-please PR #63 remains approval-gated and must not
be merged or published autonomously.

### R35 — Refuse unregistered worktree purge targets

- Status: **Awaiting Cesc review in PR #133** for issue #132 on
  `fix/refuse-unregistered-worktree-purge-r35`; the implementation head passed
  macOS CI and the PR must not be auto-merged.
- User outcome: purging malformed or stale persisted state cannot run teardown
  against, force-remove, or recursively delete the main checkout or an
  unrelated directory.
- Success signal: only a removable Git-registered non-main worktree reaches
  teardown/removal; a refused Git removal leaves its directory and branch
  intact; branch deletion occurs only after successful removal.
- macOS impact: no UI change. This is worktree cleanup behavior exercised by
  the native app.
- Persistence/security impact: treats persisted worktree paths as untrusted
  and narrows a destructive filesystem and command-execution boundary.
- Scope: `GitOperations`, `WorkstreamArchiver` and focused real-repository
  tests. Preserve the explicit Purge UI, valid teardown, tmux cleanup and
  metadata removal. No migration, entitlement, release or localization change.
- Acceptance criteria:
  1. Registered non-main worktrees resolve and retain existing force-removal.
  2. Missing, main, unrelated, locked and stale/prunable paths are rejected
     before teardown or filesystem deletion.
  3. Git refusal preserves the candidate directory and branch.
  4. The caller deletes a branch only after confirmed worktree removal.
  5. Focused XCTest and full GitHub macOS build/test pass.
- Risk: high-adjacency bounded hardening because purge is destructive. Never
  auto-merge; Cesc must review and test the PR.
- Native evidence: at implementation head `7666469`, macOS CI run
  `31934526117` passed localization parity, XcodeGen, the native build and the
  full XCTest suite including the new real-Git worktree tests. CodeQL run
  `31934526124` passed Actions and JavaScript analysis; Swift analysis was
  skipped by repository workflow configuration. The final roadmap-only head
  must remain green.
- Independence: the implementation paths and purge behavior do not overlap
  the open R16–R23/R34 changes, roadmap-only #126 or release metadata #63.

### Independent Ready queue while R35 and older PRs await review

- **R36 — Make Quick Action cancellation real:** retain the running `gh`
  process and terminate it on Cancel so a user cannot see an idle UI while a
  Close PR mutation continues in the background. Success: deterministic
  process-double tests prove cancellation, completion and single terminal
  state. Scope: `QuickActionRunner` and focused tests only; no new GitHub
  operation or permission. Independent of every open implementation PR.
- **R37 — Preserve setup-completion records through malformed entries:** decode
  setup-completion IDs independently so one invalid persisted element cannot
  erase all valid markers and unexpectedly rerun previously completed setup
  scripts. Success: mixed valid/invalid fixtures preserve valid UUIDs while
  invalid top-level data fails closed. Scope: `SetupStateStore` and focused
  persistence tests; no script content, trust or launch change. Its storage
  behavior is independent of PR #119's editor close-save path in the same view
  file and can merge in either order.
- **R38 — Keep dirty default checkouts on their current commit:** do not move a
  local default-branch ref to `origin` when its checkout has staged, unstaged
  or untracked work and cannot be safely reset. Success: temporary-remote tests
  prove clean checkouts fast-forward while dirty checkout refs, index and files
  remain unchanged. Scope: the later `updateDefaultBranch` block and focused
  Git tests; it is behaviorally separate from R35's worktree-removal block and
  can merge in either order.

R24 remains **blocked on R23 merging** because its normalized activity
vocabulary must not be duplicated while PR #128 awaits review. R25 and R27–R29
retain their documented dependencies. Issues #41, #43 and #54 remain open;
#41 needs native profiling, #43 crosses the update-execution approval gate and
#54 must not be claimed complete by the capability-only R23 slice.

- **2026-08-16 09:30 CEST:** reconciled current main, `TODO.md`, all open
  issues/PRs and their changed paths/checks, latest release and Projects v2
  scope. Selected independent R35 / issue #132 from a fresh `origin/main`
  worktree. No older PR comment, merge, release or Project mutation occurred.

## Live reconciliation — 2026-08-28 09:30 CEST

This section supersedes every earlier queue and item status. `origin/main` is
`fce9d0f`; its macOS `build-and-test`, release automation and configured CodeQL
checks are green. PRs #140 (R39), #142 (R40), #144 (R41), #146 (R42) and #148
(R43) are clean, green on macOS CI and **awaiting Cesc review**. Older PRs #117
and #126 are green at their heads but conflict with current `main`; they also
remain awaiting review. Their changed paths, behaviors and dependencies were
compared before selecting R44; none is modified, stacked on or duplicated by
this run. Release-please PR #63 remains approval-gated and must not be merged or
published autonomously. The latest published release remains v0.2.1.

GitHub Projects v2 returned `INSUFFICIENT_SCOPES`: the automation token has
`repo` and `workflow` but lacks `read:project`. No Project data or status is
inferred. Open product issues before selection were #41, #43, #54, #116, #141,
#143, #145 and #147; issue #149 records this run.

### R44 — Bound browser-state cache reads before decoding

- Status: **Awaiting Cesc review in PR #150** on
  `fix/bound-browser-state-cache-reads-r44` for issue #149. Required native
  implementation CI is green and the PR must not be auto-merged.
- User outcome: restoring or appending embedded-browser state cannot follow a
  cache symlink or allocate unbounded memory before JSON decoding.
- Success signal: a valid regular snapshot at the 1 MiB boundary decodes,
  while symlinked, oversized, non-regular and malformed candidates fail closed.
- macOS impact: embedded-browser state restoration only; no visible UI,
  accessibility, localization, shortcut or navigation behavior changes.
- Persistence/security impact: narrows a read-side local cache boundary. It
  does not change the state schema, atomic writer, cleanup, JavaScript policy,
  browser environment variable, entitlements, worktrees or release execution.
- Scope: `BrowserBridge`, focused `BrowserViewTests` and roadmap evidence only.
- Dependencies: none. Its source/test behavior is disjoint from open PRs
  #140, #142, #144, #146 and #148, conflicting older PRs #117/#126 and release
  metadata #63, so the implementations can merge in either order.
- Risk: low and reversible read-side hardening; full macOS CI is mandatory.
- Acceptance criteria:
  1. Open and inspect the same descriptor without following symbolic links.
  2. Accept only regular files at or below 1 MiB.
  3. Keep reads bounded to 1 MiB plus one detection byte if a file grows.
  4. Preserve existing valid state decoding, atomic writes and private modes.
  5. Reject malformed JSON without changing browser or persisted state.
  6. Full GitHub macOS build/test passes.
- Required evidence: focused XCTest, resource/localization checker suites,
  XcodeGen/native build, full XCTest, `git diff --check`, added-line secret
  scan and configured CodeQL.
- Evidence so far: deterministic resource/localization checker suites and live
  checks pass (10 resource declarations, 418 app keys and 15 privacy keys
  across all five locales); `git diff --check` passes. The Linux runner has no
  Swift, Xcode, XcodeGen, SwiftFormat or prek, so GitHub macOS CI is mandatory
  native evidence. At head `df351b9`, macOS CI run `33152303202` passed
  resource/localization checks, XcodeGen, the native build and the full XCTest
  suite including the new browser-state fixtures. CodeQL run `33152303132`
  passed its configured Actions and JavaScript analyses; Swift analysis was
  skipped by repository workflow configuration. The final roadmap-only head
  must also remain green.

### Independent Ready queue while R39–R44 await review

#### R45 — Bound Claude transcript parsing for the usage meter

- Status: **Ready**; no issue or implementation branch exists.
- User outcome: one oversized or malformed recent transcript cannot cause an
  unbounded in-memory read while Dockyard refreshes usage.
- Success signal: bounded line/file fixtures preserve valid recent usage and
  skip oversized input deterministically.
- Scope and impact: `ClaudeUsageParser` and focused tests only; read-only local
  transcript handling with no account access, plan estimate, transcript
  mutation, telemetry, entitlement, UI or localization change.
- Dependencies/risk/tests: none and disjoint from open PRs; low risk. Cap
  candidate files and lines before decoding, preserve valid recent totals,
  reject symlinked/non-regular/oversized input and pass focused plus full macOS
  CI.

#### R46 — Bound login-shell PATH discovery

- Status: **Ready**; no issue or implementation branch exists.
- User outcome: a stalled or noisy login-shell startup file cannot indefinitely
  delay Dockyard's command-line tool discovery.
- Success signal: deterministic process-double tests prove timeout,
  termination, output cap, successful PATH parsing and cached failure behavior.
- Scope and impact: `CommandLineTools.loginShellPath`, its private cache and
  focused tests only; no PATH precedence, Coding Agent command, permission,
  persistence, UI or localization change.
- Dependencies/risk/tests: none; source/test paths are disjoint from R43 and
  every other open implementation PR. Medium command-boundary risk; stop at a
  tested PR for Cesc after focused and full macOS CI.

#### R47 — Contain and bound `.env` port inference

- Status: **Ready**; no issue or implementation branch exists.
- User outcome: embedded-browser port inference cannot follow an escaping
  `.env` symlink or read an unbounded environment file.
- Success signal: contained bounded `.env` fixtures retain `PORT` inference,
  while escaping symlinks, non-regular and oversized candidates are ignored
  and command-line port inference still works.
- Scope and impact: `RunLauncher.inferExpectedPort` and focused port-detection
  tests only; read-side inference with no environment export, run command,
  script approval, worktree, UI, localization or entitlement change.
- Dependencies/risk/tests: none and disjoint from every open PR; low risk.
  Reuse the existing project-containment boundary, cap the read before parsing
  and pass focused plus full macOS CI.

- **2026-08-28 09:30 CEST:** reconciled current `origin/main`, `TODO.md`, open
  issues, every open PR path/behavior/check, latest release, main CI and
  Projects v2 scope. Selected independent R44 / issue #149 from a fresh
  `origin/main` worktree. No older PR comment, merge, release or Project
  mutation occurred.
