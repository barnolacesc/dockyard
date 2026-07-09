# Threat Model

Dockyard is a native macOS app that manages parallel git worktrees and runs
developer tools (shells, coding agents, dev servers) inside embedded
terminals. Its job is to execute code you point it at — so the trust model is
explicit about what runs, when, and with whose approval.

**Core stance: use Dockyard with repositories you trust.** Dockyard adds
guardrails around repo-provided automation, but a repository whose build
tooling you run (in any tool) can execute code as your user.

## Trust boundaries

### 1. Repo-provided scripts (`.dockyard.json` and fallbacks)

Projects may define `setup` / `run` / `teardown` commands in `.dockyard.json`
(or `.emdash.json`, `conductor.json`, `.superset/config.json`). These run
through the user's login shell in the worktree.

Mitigation: **scripts never run without one-time user approval.** Dockyard
fingerprints (SHA-256) the script content per project and shows the exact
commands in an approval sheet before first execution; any change to the
scripts requires re-approval. Unapproved teardown scripts are skipped during
archiving. Configs written through Dockyard's own editor are trusted
implicitly because the user just typed or reviewed them.

### 2. Shell and process execution

Dockyard spawns the user's shell for terminals, wraps run scripts in the
`dy-run` port-detection launcher, and manages tmux sessions (socket
`-L dockyard`). All of this runs as the logged-in user with the user's normal
permissions — no privilege escalation, no daemons, no root helpers.

Shell quoting is centralized in `CommandBuilder` and covered by tests
(injection via project names, branch names, and paths is part of the test
suite). Where possible, git operations use argv-style `Process` invocations
rather than shell strings.

### 3. Git and GitHub operations

Quick actions call `git` and `gh` against the user's own repositories using
the user's existing credentials/keychain. Dockyard stores no credentials of
its own.

### 4. AppleScript / Terminal automation

The only Apple Events use is the self-update flow, which opens Terminal.app to
run the update script visibly (so the user sees exactly what runs). This is
why the `com.apple.security.automation.apple-events` entitlement exists;
macOS additionally gates it behind a TCC consent prompt.

### 5. Embedded Ghostty terminal

Terminal rendering uses the Ghostty engine, tracked as a git submodule pinned
to stable release tags and built from source into an xcframework. Programs
inside terminals are ordinary child processes of the app, running as the user.

### 6. Updater

- **DMG installs:** Sparkle checks a static appcast over HTTPS. Updates must
  be EdDSA-signed with the public key pinned in Info.plist (`SUPublicEDKey`)
  and are Apple-notarized. Automatic checks are off by default
  (`SUEnableAutomaticChecks: false`).
- **Source installs:** the app runs `git fetch` on its own checkout, and the
  user-triggered update runs `git merge --ff-only` plus a local rebuild in a
  visible Terminal window. Integrity derives from the git remote the user
  cloned and their local toolchain.

## Entitlements (release builds)

| Entitlement | Why |
| --- | --- |
| `app-sandbox = false` | The app's core function is spawning shells/git/tmux against arbitrary project directories; the sandbox prohibits this. Same posture as iTerm2/Ghostty. |
| `automation.apple-events` | Self-update opens Terminal.app (see §4). |
| `device.audio-input` | Lets CLI tools inside embedded terminals request microphone access (e.g. dictation); the app itself never records. |

Debug builds additionally set `cs.disable-library-validation` to load locally
built, unsigned GhosttyKit; release builds do not.

## Non-goals

Dockyard does not attempt to defend against: a compromised local user
account, malicious tools the user installs and runs, or malicious code in
repositories the user chooses to build. It aims to never *widen* that attack
surface: no network services are opened (the `dy-run` launcher only *observes*
listening ports via `libproc`), nothing runs at elevated privilege, and no
repo content executes without consent.
