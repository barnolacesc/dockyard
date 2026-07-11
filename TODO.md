# TODO

## Fork separation (upstream cleanup follow-ups)

- [ ] Detach the repo from the fork network via GitHub Support (https://support.github.com/request) so the "forked from alltuner/factoryfloor" banner disappears and the repo gets indexed in search
- [ ] Create `barnolacesc/homebrew-tap` with the Dockyard cask — `brew install --cask barnolacesc/tap/dockyard` in README/website currently fails because the tap repo doesn't exist
- [ ] Publish `appcast.xml` at dockyard.barnola.net (Sparkle `SUFeedURL` in project.yml currently 404s, so DMG auto-updates can't work)
- [ ] Deploy the website to dockyard.barnola.net — not live yet, pending DNS (CNAME to barnolacesc.github.io in Cloudflare), GitHub Pages enablement, and a deploy workflow
- [ ] Decide on Poblenou branding (app icon skyline, `PoblenouSkyline.swift`, "Made with ❤️ in Poblenou" website footer) — keep as homage or rebrand
- [ ] If sponsorship is wanted later: set up GitHub Sponsors / Buy Me a Coffee and restore the links removed from README and the website sponsor page

## Pre-release

- [x] App screenshots on website (agent, environment, info, terminal, browser, project)

## Post-release

- [x] Auto-update mechanism (Sparkle): in-app update for direct DMG users (Settings → Updates, plus existing Check for Updates menu)

## Bugs

- [x] Branch name doesn't appear in sidebar after workstream creation until the 15s refresh timer fires. Fixed: call `refreshPathValidity` immediately in the `.workstreamWorktreeReady` handler.
- [x] Branch/workstream renames lagged up to 15s. Fixed: FSEvents `WorktreeHeadWatcher` syncs the name instantly on `.git/HEAD` change; 15s poll remains a backstop.
- [x] `AppCommit.swift` dirtied the tree on every build. Fixed: gitignored + generated via `scripts/gen-appcommit.sh` prebuild on all consuming targets.

## UI improvements

- [x] **Refactor Cmd+N behavior**: Cmd+N goes straight to the directory picker (add existing folder), Cmd+Shift+N creates a new project, the + button offers both via a menu.
- [x] **Declutter Sidebar**: Removed the Recent/A-Z segmented picker (sort defaults to recent).
- [x] **Sidebar Density**: Added a status strip (project / workstream / open-PR / waiting-agent counts + Claude usage meter), global Open PRs section, Recent workstreams section, and richer rows (agent-state dot, branch, PR, ±N uncommitted-changes hint).
- [x] Sidebar workstream rows: removed repetitive terminal icons, kept warning icon only for invalid paths
- [x] Sidebar workstream subtext: show PR title (#number) when available, fall back to branch name only when it differs from the workstream name

## Future

- [~] **Embedded Browser Claude Integration**: Foundation shipped — embedded WKWebView writes URL / title / recent console logs to `~/Library/Caches/dockyard/browser-state/<id>.json`, exposed via `DOCKYARD_BROWSER_STATE_FILE`. Full bidirectional CDP control deferred (WKWebView cannot run Chrome extensions, so this needs its own design).
- [ ] External Chrome integration: launch with --remote-debugging-port for WebMCP/CDP — dropped, doesn't unlock "Claude in Chrome" extension since that lives inside Chrome and doesn't talk CDP.
- [x] Horizontal terminal splits within a tab: split panes existed already (Cmd+Shift+T/B/Return). Added Cmd+Shift+D to toggle between horizontal (side-by-side) and vertical (stacked) layouts.

## Done
- [x] PR management: create and manage PRs from workstreams via Quick Actions


- [x] System notifications when agent needs attention (bell/urgency from Ghostty)
- [x] Embedded Ghostty terminals (Metal GPU-rendered via libghostty)
- [x] Project and workstream management with sidebar tree
- [x] Git worktrees for workstreams (branch off default branch)
- [x] .env/.env.local symlinks in worktrees (guarded by setting)
- [x] Tmux mode for Coding Agent session persistence
- [x] Claude session resume via --session-id/--resume
- [x] Auto-respawn agent on process exit (tmux pane-died hook)
- [x] Auto-rename branch via --append-system-prompt
- [x] Per-workstream permission mode (bypass prompts, context menu on +)
- [x] Agent Teams setting (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)
- [x] Deterministic port allocation per workstream (DY_PORT env var, DJB2 hash)
- [x] Dynamic workspace tabs (Info + Agent + Environment, Terminal/Browser on demand)
- [x] Terminal tabs auto-close on shell exit, agent respawns
- [x] Multi-terminal support with proper Ghostty focus management
- [x] Embedded WKWebView browser with nav bar, loading indicator
- [x] Cmd+L address bar focus, auto-focus on new browser
- [x] PR badge in workspace toolbar (links to GitHub PR)
- [x] Info tab with README.md, CLAUDE.md, AGENTS.md (cmark-gfm WKWebView, skip files < 20 bytes)
- [x] Doc tabs in project overview (shared DocFile/DocTabButton)
- [x] GitHub integration: repo info, open PRs, branch PR status (via gh CLI)
- [x] Keyboard shortcuts: all documented in HelpView, README, AGENTS.md, and website
- [x] Help view with app icon, skyline, shortcuts, credits, sponsor/bug/feature links
- [x] Settings: environment, CLI install (auto-hidden), tmux, bypass, teams, auto-rename, appearance, language, base dir, branch prefix, external apps, bleeding edge, danger zone
- [x] Project overview with editable name, git info, GitHub info, worktree list with prune, doc tabs
- [x] Workstream info with project icon, branch copy, directory, PR status, scripts, docs
- [x] Drag-and-drop directories to sidebar
- [x] dockyard:// URL scheme for single-instance behavior
- [x] CLI launcher (ff) installed via Homebrew cask binary directive
- [x] Auto-generated workstream names (operation-adjective-component)
- [x] Workstream name syncs from branch rename (every 15s)
- [x] Sidebar state persisted across restarts (JSON files in ~/.config/dockyard/)
- [x] Async git repo info, path validity, branch names (parallelized via TaskGroup)
- [x] Auto-remove projects with missing directories (with user notification)
- [x] Worktree path validation with visual feedback
- [x] Archive warning for uncommitted changes
- [x] Workstream sorting in project view (recent / A-Z)
- [x] Localization: en, ca, es, sv (all strings translated)
- [x] Script config: .dockyard.json
- [x] Environment tab: setup (auto) / run (on-demand) with Rebuild and Start/Rerun shortcuts
- [x] Port detection: dy-run launcher with libproc process tree scanning and auto browser retarget
- [x] Tmux session restore for run scripts on app relaunch
- [x] Preload agent and setup terminals in background
- [x] Occlude non-visible terminal surfaces (ghostty_surface_set_occlusion)
- [x] Update notification: versions.json check + sidebar badge + /get page
- [x] App icon with Poblenou skyline
- [x] Project icon detection (icon.svg, icon.png, logo.svg, logo.png)
- [x] Ghostty submodule pinned to v1.3.1, weekly CI compatibility test
- [x] Code signing, notarization, release-please, CI pipeline (security hardened)
- [x] Homebrew tap (barnolacesc/homebrew-tap) with cask and CLI binary
- [x] Website: Hugo + Tailwind, i18n (4 langs), sponsor page, privacy, SEO, OG image, /get page
- [x] Distribution: docs/distribution.md with automated versions.json in release workflow
- [x] Onboarding view with prerequisites, getting started, key concepts
- [x] Sentry crash reporting (added upstream, removed in 1c446df — app has no crash reporting)
- [x] Swift 6 strict concurrency migration
- [x] Security: WKWebView JS disabled, shell-escape tmux, surface destroy, git flag injection, .env symlink validation
- [x] Accessibility: labels, focus rings, keyboard-reachable hover actions
- [x] Code quality: dedup, parallelized git, cached state, consolidated timers, error propagation
- [x] Error feedback: worktree creation, non-git dir, ghostty init, project removal, Claude not found
- [x] Fix: terminal mouse selection coordinates, env script lifecycle, proc_listchildpids count
- [x] Restore full app state on launch, right-click sidebar menus, drag-and-drop tab reorder
- [x] VRA hardening phase 1 (issue #48): telemetry removed, entitlements minimized, script approval prompts
- [ ] VRA phase 2 (issue #48): SECURITY.md, PRIVACY.md, THREAT_MODEL.md, vendor-risk Q&A, install-from-source guide
- [ ] VRA phase 3 (issue #48): PR build/test CI, CodeQL, Dependabot, SHA-pinned actions, release checksums
