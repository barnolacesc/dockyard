#!/bin/sh
# Generates Sources/Models/AppCommit.swift, a build artifact embedding the current
# git short hash, project source path, and build configuration. The file is gitignored
# and regenerated before every build, so it must never be committed. Run as a prebuild
# script by every target that lists AppCommit.swift as a source (Dockyard, FFRun,
# DyAgentState) so a clean checkout always has it before compile, regardless of build
# order between targets.
set -eu

# PROJECT_DIR and CONFIGURATION are exported by Xcode build phases. Fall back to a path
# relative to this script when run standalone (e.g. from the command line).
if [ -z "${PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi
CONFIGURATION="${CONFIGURATION:-Unknown}"

HASH=$(git -C "${PROJECT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")

OUT="${PROJECT_DIR}/Sources/Models/AppCommit.swift"
printf 'enum AppCommit { static let hash = "%s"; static let sourcePath = "%s"; static let configuration = "%s" }\n' \
    "${HASH}" "${PROJECT_DIR}" "${CONFIGURATION}" > "${OUT}"
