# Dockyard Autonomous Product Roadmap

Last reconciled: 2026-09-03 against `origin/main` at
`08ec8b3f7a6105be759b6bf3721f19d646a05d0b`.

This is the product-direction record for autonomous development. GitHub issues
and pull requests remain the execution record. `TODO.md` is source material,
not an automatically trusted backlog.

The first **Current autonomous queue** is canonical. Dated **Live
reconciliation** and superseded queue sections are retained as an audit trail
and can contain stale statuses.

## Current autonomous queue — 2026-09-03 09:30 CEST

`origin/main` is `08ec8b3`; its latest macOS CI, CodeQL and Release workflows
are green. PR #170 (R54) is clean, green and **awaiting Cesc review**. PRs #117,
#126, #140, #146, #148, #152, #154, #156, #158, #160, #162, #164, #166 and
#168 passed native CI at their current heads but now conflict with `main`; they
remain awaiting review and are not modified, stacked on or duplicated here.
Release-please PR #63 remains approval-gated and must not be merged or
published autonomously. The latest published release remains v0.2.1.

GitHub Projects v2 returned `INSUFFICIENT_SCOPES`: the automation token has
`repo` and `workflow` but lacks `read:project`. No Project item or status is
inferred. `TODO.md` still contains the passive power-features tour, external
coordination and release-integrity follow-ups; none overlaps the selected
read-only metadata hardening. Issue #171 records this run.

### R55 — Bound project description metadata reads

- Status: **Awaiting Cesc review in PR #172** on
  `fix/bound-project-description-reads-r55-20260903` for issue #171. The PR
  must remain open and must not be auto-merged; GitHub macOS CI is the required
  native evidence.
- User outcome: an oversized or non-regular worktree description cannot freeze
  refresh or force unbounded allocation while Dockyard discovers repository
  metadata.
- Success signal: ordinary UTF-8 descriptions and a regular description at the
  64 KiB limit remain available; oversized, symbolic-link, directory and
  invalid UTF-8 candidates fail closed.
- macOS impact: background worktree metadata refresh only; no UI,
  accessibility, localization or shortcut behavior changes.
- Persistence/security impact: narrows a read-only repository-metadata
  boundary. The opened descriptor is checked and read with a hard cap. Cache
  semantics, worktree state, commands, scripts, entitlements and releases are
  unchanged.
- Scope: `Environment`, focused `EnvironmentDescriptionTests` and roadmap
  evidence.
- Dependencies: none. The source and test paths are disjoint from every open
  implementation PR, so changes can merge in either order.
- Risk: low and reversible read-side hardening; full GitHub macOS CI is
  mandatory.
- Acceptance criteria:
  1. A regular UTF-8 description at exactly 64 KiB remains readable.
  2. A larger description is rejected before unbounded allocation.
  3. Symbolic links and other non-regular candidates are rejected without
     blocking.
  4. Invalid UTF-8 and whitespace-only content preserve the empty result.
  5. Incremental and full metadata refresh use the same bounded reader.
  6. Focused XCTest and the full GitHub macOS build/test pass.
- Required evidence: focused XCTest, localization resource/key checks,
  XcodeGen/native build, full XCTest, `git diff --check`, added-line secret scan
  and configured CodeQL.
- Evidence so far: localization resource/key tests and repository checks pass,
  including 418 app keys and 15 privacy keys across all five locales;
  `git diff --check` and the added-line secret scan pass. The Linux host has no
  Swift, Xcode, XcodeGen, prek or SwiftFormat executable, so GitHub macOS CI is
  the mandatory native build/test evidence. At implementation head `250457c`,
  macOS CI run `33729247645` passed localization parity, XcodeGen, the native
  build, bundled-helper verification and the full XCTest suite including
  `EnvironmentDescriptionTests`. CodeQL run `33729247661` passed its configured
  analyses. The final roadmap-only head must also remain green.

### Independent Ready queue

- **R56 — Bound workstream document-preview reads.** User outcome: opening a
  workstream overview remains responsive when a README or project document is
  unexpectedly large or non-regular. Success: bounded regular previews render
  while invalid candidates show the existing empty/error state. Scope:
  `WorkstreamInfoView` and focused tests, preserving preview paths and all five
  locales. Risk: low native UI behavior; full macOS CI and proportional visual
  evidence required.
- **R57 — Bound update-check subprocess output.** User outcome: a malformed
  update helper cannot retain unbounded stdout while Dockyard checks for an
  update. Success: process-double tests prove output cap, normal parsing and
  failure handling. Scope: `AppUpdater` and focused tests only; no release,
  Sparkle, entitlement or update-install behavior change. Risk: command
  boundary; stop at a tested PR for Cesc review. Source: issue #43 and the
  current `readDataToEndOfFile` path.
- **R58 — Bound cached tmux configuration reads.** User outcome: startup cannot
  allocate unbounded memory while comparing an unexpected cached tmux config.
  Success: a bounded regular cache file preserves the existing no-rewrite fast
  path while oversized and non-regular candidates are treated as stale. Scope:
  `TmuxSession` and focused tests only; no tmux command, persistence, cleanup,
  permission, localization or entitlement change. Risk: low; full macOS CI
  required.

## Superseded autonomous queue — 2026-08-10 16:30 CEST

`origin/main` is `ceeea08`; its macOS `build-and-test`, CodeQL and release
automation checks are green. R16 / PR #113 is healthy and **awaiting Cesc
review**; it changes `RunLauncher`, `WorkstreamEnvironment` and focused tests.
Release-please PR #63 changes only version/changelog metadata, remains
approval-gated and must not be merged or published autonomously. The latest
published release remains v0.2.1.

GitHub Projects v2 returned `INSUFFICIENT_SCOPES` because the automation token
has `repo` and `workflow` but lacks `read:project`. No Project data or status is
inferred. Open implementation issues at selection were #41, #43, #54 and #112;
issue #114 records this run.

### R17 — Protect tmux diagnostic state

- Status: **Awaiting Cesc review in PR #115** on
  `fix/private-tmux-diagnostics` for issue #114. The PR must not be
  auto-merged.
- User outcome: tmux diagnostic output is not left readable by other local
  users after first creation or when an older permissive cache exists.
- Success signal: constructing a tmux command creates or repairs the Dockyard
  cache directory to `0700` and `tmux-stderr.log` to `0600` before shell
  redirection, while preserving existing log bytes.
- macOS impact: tmux command preparation only; no UI, accessibility,
  localization or visual behavior changes.
- Persistence/security impact: narrows local diagnostic-file permissions. Tmux
  commands, session names, app-restart persistence, archive/purge cleanup,
  entitlements and release behavior remain unchanged.
- Scope: `TmuxSession`, focused `TmuxSessionTests` and roadmap evidence only.
- Risk: low and reversible; full GitHub macOS CI is mandatory.
- Acceptance criteria:
  1. First use creates the cache directory as `0700` and stderr log as `0600`.
  2. Existing `0755`/`0644` modes are repaired without replacing log content.
  3. Diagnostic state exists before the generated command can use `2>>`.
  4. Existing tmux command-composition and shell-parsing tests remain green.
  5. Full GitHub macOS build/test passes.
- Required evidence: focused XCTest, full `macos-15` CI, CodeQL as configured,
  localization parity, diff and secret checks.
- Native evidence: at implementation head `12200ab`, macOS CI run
  `31399327020` passed localization parity, XcodeGen, the native build and the
  full XCTest suite including `TmuxSessionTests`. CodeQL run `31399327146`
  passed Actions and JavaScript analysis; Swift analysis was skipped by the
  repository's PR workflow configuration. The final roadmap-only head must
  also remain green.
- Independence: PR #113 changes environment activation paths; PR #63 changes
  release metadata. R17 changes tmux diagnostic setup and its tests, so the
  implementations can merge in either order. Roadmap updates use this
  top-level canonical queue to avoid conflicting dated audit-log appends.

### Independent Ready queue while R16 and R17 await review

- **R18 — Add the passive power-features tour:** expose existing shortcut
  hints, usage meters, tmux persistence and archive semantics without launching
  commands or changing persisted workstreams. One `TourFlow`, controller tests,
  five localizations and native visual/accessibility evidence; source is the
  remaining unchecked tour item in `TODO.md`.
- **R19 — Contain close-tab editor saves:** resolve the unsaved-editor close
  path through `WorkspaceFileAccess` before writing, matching ordinary saves
  and rejecting absolute, traversal, same-prefix and escaping-symlink paths.
  This file-write boundary is approval-gated; focused tests and full macOS CI
  are required.
- **R20 — Keep watcher-created state directories private:** create and repair
  run-state and agent-state watcher directories as `0700` before attaching
  filesystem observers. Scope is `PortDetector`, `AgentStateStore` and focused
  tests; state schemas, writers and watcher recovery behavior remain unchanged.

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
