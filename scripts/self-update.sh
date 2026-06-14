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
    echo "Local main is ahead of origin/main; nothing to pull."
else
    # Diverged: replay local commits on top of origin/main, but never clobber real work.
    if [ -n "$(git status --porcelain)" ]; then
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
fi

echo "Building Dockyard…"
./scripts/dev.sh "$BUILD_MODE"

if [ "$BUILD_MODE" = "install-bg" ]; then
    echo "Update complete. Restart Dockyard when ready."
else
    echo "Update complete. Dockyard has relaunched."
fi
