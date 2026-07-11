# Privacy

Dockyard collects **no telemetry, no analytics, and no crash reports**.
There is no account, no login, and no identifier of any kind. (Earlier
versions had optional anonymous usage analytics; the code was removed
entirely, and on first launch after updating the app deletes the old
anonymous installation ID from its preferences.)

## Network connections the app makes

| Connection | When | What is sent |
| --- | --- | --- |
| `https://dockyard.barnola.net/appcast.xml` (Sparkle) | DMG installs only, when checking for updates | Standard HTTP request; Sparkle sends the app version in the user agent |
| `git fetch` on Dockyard's own source checkout | Source installs only, periodic update check | Normal git traffic to whatever remote *you* cloned from |

That is the complete list. Everything else that touches the network is
something you run yourself:

- **git / GitHub operations** (fetch, push, PR creation via `gh`) go to your
  repository's own remotes with your own credentials.
- **Terminals and coding agents** (Claude Code, Codex, etc.) are your tools
  running under your account; their network behavior is governed by their own
  vendors' policies, not Dockyard's.
- **The embedded browser** loads whatever URL you point it at (typically your
  local dev server). App Transport Security is relaxed
  (`NSAllowsArbitraryLoads`) solely so plain-HTTP `localhost` dev servers work.

## Local data

Everything Dockyard stores stays on your machine:

| Location | Contents |
| --- | --- |
| UserDefaults (`com.barnolacesc.dockyard`) | Project paths, workstream metadata, settings, sidebar state, approved-script fingerprints |
| `~/Library/Caches/dockyard/` | Run-state JSON (detected ports), generated tmux config, and — only when "Detailed logging" is enabled (default off) — launch logs that include script commands and their environment variables |
| `~/.dockyard/worktrees/` | Your git worktrees (your own code) |

The optional ".env symlink" feature links your project's `.env` into new
worktrees so dev servers keep working. The file never leaves your machine and
Dockyard never reads its contents.

## Website

The project website (dockyard.barnola.net) is a static site and is unrelated
to what the app does at runtime.
