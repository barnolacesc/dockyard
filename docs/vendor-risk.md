# Vendor Risk Assessment — Quick Answers

Answers to the questions corporate security reviews usually ask about
Dockyard. Details live in [SECURITY.md](../SECURITY.md),
[PRIVACY.md](../PRIVACY.md), and [THREAT_MODEL.md](../THREAT_MODEL.md).

**What is it?** A native macOS app (Swift/SwiftUI, MIT-licensed, source on
GitHub) that manages parallel git worktrees and embeds terminals/browsers for
running coding agents and dev servers. Comparable risk class to iTerm2 or
Ghostty.

**What data leaves the device?** None initiated by the app except update
checks: the Sparkle appcast request (DMG installs) or `git fetch` on the
app's own checkout (source installs). No telemetry, no analytics, no crash
reporting, no accounts. See PRIVACY.md for the full table.

**What network endpoints are contacted?** `dockyard.barnola.net` (appcast,
DMG installs only) and the git remote of the app's own source checkout
(source installs only). All other traffic (git, `gh`, coding-agent CLIs,
browser tabs) is user-initiated toward the user's own services.

**Does it execute code? As whom?** Yes — that is its purpose. Shells,
scripts, and tools run as the logged-in user, never elevated. Repo-provided
scripts (`.dockyard.json`) require one-time user approval per project and
re-approval whenever their content changes.

**Does it process secrets or environment variables?** It passes the user's
normal shell environment to terminals, injects workstream metadata variables
(`DY_*` and compatibility equivalents), and can optionally symlink a
project's `.env` into worktrees. It never reads secret values itself and
never transmits them. Optional detailed logging (default off) writes script
launch environments to local log files only.

**What local files does it read/write?** Project directories the user adds,
worktrees under `~/.dockyard/worktrees/`, preferences in UserDefaults, and
caches under `~/Library/Caches/dockyard/`. Config is read from
`.dockyard.json` (or emdash/conductor/superset fallbacks) in the project.

**What macOS privileges/entitlements does it need?** Not sandboxed (it
spawns shells/git/tmux — same as other terminal apps), Apple Events (visible
Terminal window for self-update), audio-input (so terminal programs can
request the mic). Nothing else; camera/contacts/calendars/location/photos
entitlements were removed. TCC still prompts for anything sensitive.

**How are updates delivered and verified?** DMG: Developer ID-signed,
notarized, Sparkle updates EdDSA-signed against a key pinned in the app;
automatic checks off by default. Source installs: user-visible
`git fetch` + `merge --ff-only` + local rebuild — the chain of custody is
your git remote plus your local toolchain. Corporate deployments that
disallow DMGs can build from source; see
[install-from-source.md](install-from-source.md).

**How are vulnerabilities reported and fixed?** Privately via GitHub
Security Advisories; fixes ship in the next patch release. Only the latest
release is supported.

**Supply chain?** Dependencies are minimal: Sparkle (SPM) and the Ghostty
terminal engine as a git submodule pinned to stable release tags and built
from source. The Monaco editor bundle is built from the in-repo `editor/`
project. No third-party analytics or networking SDKs.

**Supported platforms / cadence.** macOS 14+, Apple Silicon and Intel.
Releases are frequent (release-please, semantic versioning); changelog in
`CHANGELOG.md`.
