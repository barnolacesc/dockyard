#!/bin/sh
# Pull the latest main and rebuild Dockyard, invoked by the in-app updater.
#
# Hardened and idempotent:
#   - Discards the generated AppCommit.swift artifact so it never blocks the pull.
#   - Switches to main if on another branch.
#   - Fast-forwards when behind; rebases local commits when branches have diverged
#     (so nothing is lost); no-ops when already up to date.
#   - Refuses to touch real uncommitted changes, and aborts cleanly on a rebase
#     conflict instead of leaving a half-finished state.
#
# Usage: scripts/self-update.sh [br|install|install-bg]   (run from the repo root)
#   br          rebuild and relaunch the debug build (dev)
#   install     rebuild, swap the /Applications bundle, and relaunch it (release)
#   install-bg  rebuild and swap the bundle without relaunching
set -eu

BUILD_MODE="${1:-br}"

# Run from the repo root regardless of caller cwd.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Fetching latest main…"
git fetch origin main

# Re-exec the newest version of this script so fixes to the update flow itself apply
# on this run, not the next one — the local copy may be the very thing that's broken.
if [ -z "${DOCKYARD_SELF_UPDATE_REEXEC:-}" ] \
    && [ "$(git rev-parse HEAD:scripts/self-update.sh)" != "$(git rev-parse origin/main:scripts/self-update.sh)" ]; then
    echo "Update flow changed upstream; re-running with the latest script…"
    latest="$(git show origin/main:scripts/self-update.sh)"
    DOCKYARD_SELF_UPDATE_REEXEC=1 exec sh -c "$latest" "$SCRIPT_DIR/self-update.sh" "$BUILD_MODE"
fi

# Drop changes to the generated build artifact (regenerated every build) so it never
# blocks a checkout/rebase. Harmless once the file is gitignored on newer revisions.
git checkout -- Sources/Models/AppCommit.swift 2>/dev/null || true

# Make sure we're on main.
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
    git checkout main
fi

local_head="$(git rev-parse @)"
remote_head="$(git rev-parse origin/main)"
base="$(git merge-base @ origin/main)"

if [ "$local_head" = "$remote_head" ]; then
    echo "Already up to date."
elif [ "$local_head" = "$base" ]; then
    echo "Fast-forwarding to origin/main…"
    git merge --ff-only origin/main
elif [ "$remote_head" = "$base" ]; then
    echo "Local main is ahead of origin/main by $(git rev-list --count origin/main..@) commit(s); nothing to pull."
else
    # Diverged: replay local commits on top of origin/main, but never clobber real work.
    # Untracked files are ignored: a rebase cannot touch them, and local tooling
    # state (e.g. .claude/) would otherwise block every update.
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "Cannot update automatically: you have uncommitted changes in $(pwd)."
        echo "Commit or stash them, then try again."
        exit 1
    fi
    echo "Branches diverged; rebasing local commits onto origin/main…"
    if ! git rebase origin/main; then
        git rebase --abort 2>/dev/null || true
        echo "Update needs a manual merge (rebase conflict). Resolve it in $(pwd) and rebuild."
        exit 1
    fi
    echo "Note: local main still carries $(git rev-list --count origin/main..@) local commit(s) on top of origin/main."
fi

echo "Building Dockyard…"
./scripts/dev.sh "$BUILD_MODE"

if [ "$BUILD_MODE" = "install-bg" ]; then
    echo "Update complete. Restart Dockyard when ready."
else
    echo "Update complete. Dockyard has relaunched."
fi
