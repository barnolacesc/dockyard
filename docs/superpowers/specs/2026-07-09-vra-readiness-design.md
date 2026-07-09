# VRA Readiness Design (issue #48)

Goal: make Dockyard approvable for corporate workstation use. Primary deployment is
**build from source** (`git clone` + `./scripts/dev.sh install`); DMG distribution is
secondary. Three phases, each an independent PR.

## Phase 1 — App hardening

### 1.1 Delete telemetry
- Remove `Sources/Models/Telemetry.swift` and all call sites:
  `DockyardApp.swift:224`, `WorkstreamArchiver.swift:69`, `SettingsView.swift:348`,
  `TerminalContainerView.swift` (4 tab-open events), `ContentView.swift:596`.
- Remove the Settings toggle (`SettingsView.swift:24`, ~408) and its strings from all 5 locales.
- On launch, delete legacy UserDefaults keys `dockyard.installationID` and
  `dockyard.telemetryEnabled` so no anonymous ID persists.
- `xcodegen generate` after removing the file.

### 1.2 Minimize entitlements
- `Resources/dy.entitlements` (release): keep only `app-sandbox=false`,
  `automation.apple-events`, `device.audio-input`. Drop camera, addressbook, calendars,
  location, photos-library.
- `Resources/dy-local.entitlements` (debug): same set + `cs.disable-library-validation`.
- `project.yml`: remove usage descriptions for dropped capabilities (camera, contacts,
  calendars, location ×2, photos, bluetooth). Keep Apple Events, microphone,
  audio-capture, local network.
- Rationale recorded in docs (Phase 2): Apple Events = self-update scripts Terminal;
  audio-input = dictation / audio CLI tools inside embedded terminals; sandbox off =
  app's core function is spawning shells/git/tmux in arbitrary project directories.

### 1.3 First-run script confirmation (ScriptTrustStore)
Problem: creating a workstream from any cloned repo executes that repo's
`.dockyard.json` (or `.emdash.json`/`conductor.json`/`.superset/config.json`)
setup/run/teardown through the user's login shell with no prompt.

Design:
- New `Sources/Models/ScriptTrustStore.swift`:
  - `hash(of: ScriptConfig) -> String` — SHA-256 over the setup/run/teardown strings
    (stable framing, nil-safe).
  - `isTrusted(projectDirectory: String, config: ScriptConfig) -> Bool`
  - `trust(projectDirectory: String, config: ScriptConfig)`
  - Storage: UserDefaults `dockyard.trustedScripts` as `[projectPath: hash]`.
  - Configs with no scripts are implicitly trusted.
- Gate points:
  - **Setup** (`TerminalContainerView.startSetupIfNeeded`): if untrusted, do not run;
    present a confirmation sheet showing the exact setup/run/teardown commands
    (monospaced) with source filename, buttons **Run Scripts** / **Not Now**.
    Approve → store hash, start setup. Decline → setup card in Info tab remains,
    user can approve later from there.
  - **Run** (`EnvironmentTabView` Start button): if untrusted, same sheet before launching.
  - **Teardown** (`ScriptConfig.runTeardown`, called by WorkstreamArchiver): if
    untrusted, skip teardown silently (log only) — no prompt mid-archive.
- Editing scripts in the Info panel auto-trusts the saved result (the user just typed them).
- Re-prompt automatically when scripts change (hash mismatch).
- All new strings localized in en/ca/de/es/sv.
- Unit tests: hashing stability, nil script fields, trust/invalidate cycle, empty config.

## Phase 2 — Security & privacy docs
- `SECURITY.md`: report via GitHub Security Advisories; supported version = latest release.
- `PRIVACY.md`: no telemetry; full outbound list (self-updater `git fetch` on the app's
  own checkout; Sparkle appcast at francesc.barnola.net — DMG builds only); local data
  inventory (UserDefaults keys, `~/Library/Caches/dockyard/`, `~/.dockyard/worktrees/`).
- `THREAT_MODEL.md`: trust boundaries — repo-provided scripts (mitigated by 1.3),
  shell/tmux execution, AppleScript/Terminal automation, embedded Ghostty, updater;
  explicit "use with trusted repositories" stance. Seed from
  `docs/architecture-security-review.md`.
- `docs/vendor-risk.md`: Q&A from issue #48 (data leaving device, endpoints, local
  files, secrets/env handling, code execution model, entitlements justification,
  update signing/verification, vuln reporting, supported macOS versions).
- `docs/install-from-source.md`: prerequisites (Xcode, zig, bun, xcodegen), clone +
  `./scripts/dev.sh install`, self-update flow, chain-of-custody argument for
  source builds.

## Phase 3 — CI & supply chain
- `.github/workflows/ci.yml`: PR/push to main on macOS — `xcodegen generate`, build,
  test; Ghostty xcframework cached by submodule SHA (reuse `test-ghostty.yml` approach).
- `.github/workflows/codeql.yml`: Swift, PR + weekly schedule.
- `.github/dependabot.yml`: github-actions, npm (`editor/`), swift, gitsubmodule.
- Pin all action refs by SHA.
- `test-ghostty.yml`: add path-based triggers (ghostty/, scripts/, project.yml).
- `release.sh`: emit SHA-256 checksums next to the DMG.
- Out of scope (documented in issue close): SBOM, MDM managed preferences — only
  relevant for packaged enterprise distribution, which is not the deployment model.

## Acceptance
- Release build contains no telemetry code or endpoint; only minimal entitlements.
- Repo-provided scripts never execute without one-time user approval per project+content.
- Docs answer the standard VRA questionnaire.
- CI proves clean build/test on fresh clone; static analysis and dependency updates automated.
