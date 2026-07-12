#!/usr/bin/env bash
# ABOUTME: Builds, drives, records, and post-processes the deterministic website demo.
# ABOUTME: Run once after granting Screen Recording and Accessibility permissions.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

BUILD_DIR="$ROOT/build/demo-capture/derived"
WORK_DIR="$ROOT/.build/demo-capture"
RAW="$WORK_DIR/dockyard-tour-raw.mp4"
MEDIA="$ROOT/website/site/media"
RECORDER_APP="$BUILD_DIR/Build/Products/Debug/Dockyard Demo Recorder.app"
RECORDER_EXECUTABLE="$RECORDER_APP/Contents/MacOS/Dockyard Demo Recorder"
PERMISSION_STATUS="$WORK_DIR/screen-recording-permission.txt"
CAPTURE_STATUS="$WORK_DIR/capture-status.txt"
DEMO_READY="/tmp/dockyard-demo-process.pid"
SPM_CACHE="$HOME/Library/Caches/dockyard/spm"
RECORDER_PID=""

cleanup() {
  status=$?
  if [ -n "$RECORDER_PID" ] && kill -0 "$RECORDER_PID" 2>/dev/null; then
    kill "$RECORDER_PID" 2>/dev/null || true
    wait "$RECORDER_PID" 2>/dev/null || true
  fi
  pkill -xf '.*/Contents/MacOS/Dockyard Debug' 2>/dev/null || true
  pkill -xf '.*/Contents/MacOS/Dockyard Demo Recorder' 2>/dev/null || true
  rm -rf "${DOCKYARD_DEMO_ROOT:-/tmp/dockyard-website-demo}"
  exit "$status"
}
trap cleanup EXIT INT TERM

require() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing $1. $2" >&2; exit 1; }; }
require xcodebuild "Install Xcode and select it with xcode-select."
require xcodegen "Install XcodeGen (brew install xcodegen)."
require ffmpeg "Install ffmpeg (brew install ffmpeg)."
require ffprobe "Install ffmpeg (brew install ffmpeg)."

os_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$os_major" -ge 14 ] || { echo "error: macOS 14 or newer is required." >&2; exit 1; }
[ -n "${DISPLAY:-}${SSH_TTY:-}" ] || pgrep -x WindowServer >/dev/null || { echo "error: no graphical macOS session is available." >&2; exit 1; }
[ -d ghostty/zig-out/share/terminfo ] && [ -d ghostty/zig-out/share/ghostty ] || {
  echo "error: Ghostty resources are missing. Run: cd ghostty && zig build" >&2; exit 1;
}

mkdir -p "$WORK_DIR" "$MEDIA"
rm -f "$RAW" "$MEDIA"/*.mp4 "$MEDIA"/*.jpg

echo "==> Generating the Xcode project"
./scripts/gen-appcommit.sh
xcodegen generate

echo "==> Building Dockyard, UI tour, and recorder"
xcodebuild -project Dockyard.xcodeproj -scheme DockyardDemoUITests -configuration Debug \
  -derivedDataPath "$BUILD_DIR" -clonedSourcePackagesDirPath "$SPM_CACHE" \
  -skipPackagePluginValidation build-for-testing
if [ ! -x "$RECORDER_EXECUTABLE" ]; then
  xcodebuild -project Dockyard.xcodeproj -scheme DemoRecorder -configuration Debug \
    -derivedDataPath "$BUILD_DIR" -clonedSourcePackagesDirPath "$SPM_CACHE" \
    -skipPackagePluginValidation build
fi

echo "==> Checking one-time macOS privacy permissions"
rm -f "$PERMISSION_STATUS"
open -W -n "$RECORDER_APP" --args --check-permissions --status-file "$PERMISSION_STATUS" || true
[ "$(cat "$PERMISSION_STATUS" 2>/dev/null || true)" = "allowed" ] || {
  echo "error: Screen Recording permission is missing for Dockyard Demo Recorder." >&2
  echo "       Enable it in System Settings > Privacy & Security > Screen & System Audio Recording." >&2
  exit 1
}

export DOCKYARD_DEMO_MODE=1
export DOCKYARD_DEMO_AUTOPLAY=1
export DOCKYARD_DEMO_ROOT="$WORK_DIR/fixture"
export DOCKYARD_DEMO_READY_FILE="$DEMO_READY"

echo "==> Recording the Dockyard window"
rm -f "$CAPTURE_STATUS" "$DEMO_READY"
open -n "$RECORDER_APP" --args --output "$RAW" --target-pid-file "$DEMO_READY" --duration 55 --completion-file "$CAPTURE_STATUS"
RECORDER_PID=""
xcodebuild -project Dockyard.xcodeproj -scheme DockyardDemoUITests -configuration Debug \
  -derivedDataPath "$BUILD_DIR" -clonedSourcePackagesDirPath "$SPM_CACHE" \
  -skipPackagePluginValidation test-without-building
for _ in {1..120}; do
  [ "$(cat "$CAPTURE_STATUS" 2>/dev/null || true)" = "completed" ] && break
  sleep 1
done
RECORDER_PID=""
[ "$(cat "$CAPTURE_STATUS" 2>/dev/null || true)" = "completed" ] || {
  echo "error: recorder did not complete within 120 seconds." >&2
  exit 1
}
[ -s "$RAW" ] || { echo "error: recorder produced no video." >&2; exit 1; }

encode() {
  input=$1 output=$2 start=$3 duration=$4
  ffmpeg -hide_banner -loglevel error -y -ss "$start" -t "$duration" -i "$input" \
    -vf "fps=30,scale=1920:-2:flags=lanczos" -an -c:v libx264 -preset slow -crf 21 \
    -pix_fmt yuv420p -movflags +faststart "$output"
}
poster() {
  input=$1 output=$2 at=$3
  ffmpeg -hide_banner -loglevel error -y -ss "$at" -i "$input" -frames:v 1 \
    -vf "scale=1600:-2:flags=lanczos" -c:v mjpeg -q:v 3 "$output"
}

echo "==> Producing web media"
encode "$RAW" "$MEDIA/dockyard-tour.mp4" 0 54
encode "$RAW" "$MEDIA/workstreams.mp4" 0 9
encode "$RAW" "$MEDIA/coding-agent.mp4" 5 14
encode "$RAW" "$MEDIA/live-preview.mp4" 20 14
encode "$RAW" "$MEDIA/editor-and-pr.mp4" 34 15
poster "$MEDIA/dockyard-tour.mp4" "$MEDIA/dockyard-tour.jpg" 3
poster "$MEDIA/workstreams.mp4" "$MEDIA/workstreams.jpg" 2
poster "$MEDIA/coding-agent.mp4" "$MEDIA/coding-agent.jpg" 7
poster "$MEDIA/live-preview.mp4" "$MEDIA/live-preview.jpg" 7
poster "$MEDIA/editor-and-pr.mp4" "$MEDIA/editor-and-pr.jpg" 7

echo "==> Verifying output media"
for file in "$MEDIA"/*.mp4 "$MEDIA"/*.jpg; do [ -s "$file" ] || { echo "error: empty output $file" >&2; exit 1; }; done
for file in "$MEDIA"/*.mp4; do
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate \
    -show_entries format=duration -of default=noprint_wrappers=1 "$file"
done

echo "==> Website demo capture complete"
echo "    Final media: $MEDIA"
echo "    Raw intermediate (gitignored): $RAW"
