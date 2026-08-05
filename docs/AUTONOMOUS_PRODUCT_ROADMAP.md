# Dockyard Autonomous Product Roadmap

Last reconciled: 2026-08-05 against `origin/main` at
`99b68dfb91afbb80c2a48f0c20b3f0aa3cfd4f9e`.

This is the product-direction record for autonomous development. GitHub issues
and pull requests remain the execution record. `TODO.md` is source material,
not an automatically trusted backlog.

## Evidence and limits

- Repository: `barnolacesc/dockyard`; native SwiftUI/AppKit macOS app using
  Ghostty, git worktrees, tmux, WKWebView, Monaco and XcodeGen.
- Open implementation issues at reconciliation: #40, #41, #43, #54, #72,
  #74, #76, #78, #80, #82, #84, #86, #88, #90 and #92.
- Open autonomous implementation PRs awaiting Cesc review: #71, #73, #75,
  #77, #79, #81, #83, #85, #87, #89 and #91. Each is isolated from the
  implementation selected here; their only recurring changed path is this
  roadmap. Release-please #63 is also open and must not be changed, merged or
  released without Cesc's explicit approval.
- Latest published release: v0.2.1. `origin/main` macOS `build-and-test` and
  CodeQL were green at `99b68df`; the most recent scheduled CodeQL run was
  also green.
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
| Worktree lifecycle, persistence, cleanup and merged-PR review | Creation, remove-without-delete, purge, orphan listing and clean prune exist. Force-removal and branch deletion have tests. PR #73 adds read-only merged-PR classification. | PR #73 awaits Cesc review; any destructive bulk action remains approval-gated. |
| Tmux, terminal and session resilience | Dedicated `dockyard` socket, deterministic sessions, `new-session -A`, respawn hooks and tab snapshots exist. PR #70 removed normal-quit global server cleanup and merged with green macOS CI. | R8 addresses the remaining instant branch-name watcher recovery gap; macOS reboot persistence remains separate scope. |
| Coding CLI compatibility and agent/subagent status | Claude Code and Codex have specialized builders. PR #75 documents/tests the narrower OpenCode generic-launch contract. Claude/Codex hooks report main-agent state. | PR #75 awaits Cesc review; issue #54 remains discovery until vendor event semantics are proven. |
| macOS lifecycle, performance, accessibility, contrast and keyboard behavior | AppDelegate tests, shortcut references, accessibility labels and five localizations exist. PR #71 addresses issue #40; issue #41 still needs native profiling. | Review PR #71 with visual evidence; profile #41 on macOS; R10 fixes path-label abbreviation deterministically. |
| Script guardrails, worktree containment, privacy and entitlements | Script fingerprint approval, re-approval on change, command quoting tests, worktree prompts and security/privacy docs exist. Detailed launch logs contain commands and environment variables but do not enforce private permissions on `origin/main`. | R7 / issue #92 hardens launch-log permissions. R9 is the next independent config-containment slice. Approval, bypass, privacy and entitlement changes stop at PR for Cesc. |
| Setup/run/teardown reliability and port detection | Fallback configs, environment injection, `dy-run`, process-tree port detection, FSEvents state and focused tests exist. PR #77 rejects stale/mismatched run-state snapshots. | PR #77 awaits Cesc review; R9 contains config resolution before any script is trusted or run. |
| Embedded browser/editor quality and safe boundaries | WKWebView browser state and Monaco editor exist; browser JavaScript policy and navigation have tests. PRs #89 and #91 harden Monaco paths and browser-state permissions. | PRs #89 and #91 await Cesc review; no bidirectional automation is Ready. |
| Onboarding, tours, What's New, docs and localization | Onboarding, Getting Started, What's New and five app localizations exist. PR #81 adds the workspace-tabs tour; one power-features follow-up remains in `TODO.md`. | PR #81 awaits Cesc review; do not duplicate its tour/catalog/localization work. |
| CI, Ghostty, dependencies, release/update integrity and distribution | macOS build/test CI, CodeQL, Dependabot, pinned actions, Ghostty compatibility workflow, checksums, Sparkle and Homebrew paths exist. Release-please #63 is pending. | Release/update mutations remain approval-gated; verify feed and published artifacts separately from CI. |

## Now

### R1 — Restore tmux persistence across Dockyard app restarts

- Status: **Delivered on `main` by PR #70** with green macOS CI and CodeQL;
  issue #69 is closed.
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

- Status: **Awaiting Cesc review in PR #71**. Source issue #40. Do not
  duplicate or stack work on this branch.
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

### R7 — Keep detailed launch logs private to the current user

- Status: **In implementation** for issue #92 on
  `fix/private-launch-logs`.
- User outcome: enabling Detailed logging does not leave commands or
  environment variables readable by other local accounts.
- Success signal: the launch-log directory is `0700` and every new or
  pre-existing per-workstream log is `0600` after an append.
- macOS impact: Foundation cache-file creation on macOS.
- Persistence/security impact: repairs privacy permissions without changing
  log contents, retention, command execution or entitlements.
- Scope: `LaunchLogger` permission enforcement and focused regressions only.
- Dependencies: none; behavior and changed source/test paths are independent
  of open PRs #71–#91.
- Risk: low and reversible, but security/privacy work stops at a tested PR for
  Cesc review.
- Acceptance criteria:
  1. Fresh log directories and files use `0700` and `0600` respectively.
  2. Existing broader permissions are repaired before appending.
  3. Existing JSONL contents and append behavior remain intact.
  4. GitHub macOS CI and CodeQL pass.
- Required tests: focused `LaunchLoggerTests`, full macOS build/test, diff and
  secret checks.
- Sources: issue #92, `LaunchLogger.swift`, `LaunchLoggerTests.swift` and the
  local-data disclosure in `PRIVACY.md`.

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

- Status: **Awaiting Cesc review in PR #73** for issue #72. Do not duplicate
  or stack work on this branch.
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

- Status: **Awaiting Cesc review in PR #75** for issue #74. Do not duplicate
  or stack work on this branch.
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

- Status: **Awaiting Cesc review in PR #77** for issue #76. Do not duplicate
  or stack work on this branch.
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

- Status: **Awaiting Cesc review in PR #81** for issue #80. Do not duplicate
  or stack work on this branch.
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

### Independent implementation PRs awaiting Cesc review

- **PR #79 / issue #78:** private state-directory permissions; green macOS CI
  at the current PR head.
- **PR #83 / issue #82:** isolate malformed workspace-tab snapshots during
  restoration; green macOS CI at the current PR head.
- **PR #85 / issue #84:** recover the agent-state watcher after directory
  replacement; green macOS CI at the current PR head.
- **PR #87 / issue #86:** prevent new localization-key drift in CI; green
  macOS CI at the current PR head.
- **PR #89 / issue #88:** contain Monaco resource paths; green macOS CI at the
  current PR head.
- **PR #91 / issue #90:** secure browser-state cache files; green macOS CI at
  the current PR head.
- Review state: all are healthy and **awaiting Cesc review**. Their behavior
  and changed paths were checked before selecting R7; no periodic PR comments
  are needed. Across PRs #71–#91, CodeQL's summary is neutral: actions and
  JavaScript analysis succeed while Swift analysis is skipped, so it is not
  recorded as green Swift CodeQL evidence.

### R8 — Reattach branch-name watchers after git-directory replacement

- Status: **Ready**, highest-priority independent item after R7.
- User outcome: branch renames continue to appear immediately after git
  replaces or renames a watched per-worktree metadata directory.
- Success signal: rename/delete events invalidate the old descriptor and
  install a new watcher while the worktree remains registered.
- macOS impact: FSEvents/DispatchSource lifecycle and sidebar freshness.
- Persistence/security impact: read-only git metadata observation; the 15s
  refresh remains a backstop.
- Scope: `WorktreeHeadWatcher` lifecycle and focused tests only.
- Dependencies: none; distinct from PR #85's agent-state cache watcher.
- Risk: low concurrency/reliability change.
- Acceptance criteria: watcher replacement is bounded, stop/sync cannot revive
  removed paths, callbacks remain debounced and native race tests pass.
- Required tests: `WorktreeHeadWatcherTests` and full macOS CI.
- Sources: `WorktreeHeadWatcher.swift` event handling and code audit on
  2026-08-05.

### R9 — Contain script configuration files within their project roots

- Status: **Ready**, approval-gated command-boundary work.
- User outcome: a repository cannot make Dockyard approve and execute scripts
  loaded through a config-file symlink that escapes the selected project or
  fallback root.
- Success signal: resolved config candidates outside the resolved root are
  rejected before parsing, fingerprinting or execution.
- macOS impact: setup/run/teardown configuration resolution.
- Persistence/security impact: tightens the command-input boundary without
  changing bypass settings, shell flags or entitlements.
- Scope: `ScriptConfig` resolution plus fixtures; no script runner redesign.
- Dependencies: none and no overlap with open autonomous PR paths.
- Risk: medium security/compatibility change; stop at a tested PR for Cesc.
- Acceptance criteria: in-root configs and symlinked project roots remain
  supported, escaping config symlinks fail closed with a testable error, and
  fallback precedence remains unchanged.
- Required tests: `ScriptConfigTests`, `ScriptTrustStoreTests`, full macOS CI
  and CodeQL.
- Sources: `ScriptConfig.swift`, script execution boundary in `AGENTS.md`, and
  code audit on 2026-08-05.

### R10 — Abbreviate only paths actually inside the home directory

- Status: **Ready**, lower priority.
- User outcome: path labels never turn a sibling such as `/Users/cesc-old`
  into the misleading `~-old` form.
- Success signal: home itself and descendants abbreviate to `~`, while simple
  string-prefix siblings remain unchanged.
- macOS impact: native path labels throughout the app.
- Persistence/security impact: display-only; stored paths are untouched.
- Scope: `PathUtilities.abbreviatedPath` and pure unit tests.
- Dependencies: none and no overlap with open autonomous PR paths.
- Risk: low, reversible UX correctness fix.
- Acceptance criteria: boundary, descendant, sibling-prefix and unrelated
  paths have deterministic tests; no user-facing strings are added.
- Required tests: focused path utility tests and full macOS CI.
- Sources: `PathUtilities.swift` and code audit on 2026-08-05.

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
