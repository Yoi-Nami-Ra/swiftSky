#!/bin/bash
# 021 (SKY-19): observe the macOS app's frames with lldb, for 001's checks 4 and 5. The macOS twin of
# probe.sh (SKY-18, iOS simulator); read that script's header and quickstart.md for the method.
#
# Usage: specs/021-ios-gpu-frame-capture/probe-macos.sh
#   Builds the Debug macOS app, launches it with `open -n`, with
#   --no-ship --no-debug-overlay, attaches lldb, and prints two parts:
#   1. COUNTS: hit counts over 10 s for draws, pipeline bindings, presents, viewport changes and
#      pipeline-state / buffer creation (creations and viewport changes print a backtrace).
#   2. SAMPLES: two samples, 5 s apart, of the bound pipeline, the bound vertex buffer (address, label,
#      length, contents as floats) and the draw's arguments (primitive type, start, count).
# After the COUNTS it checks them: it exits 1 with a FAIL line for each count that breaks check 4 or 5, or
# for a breakpoint that resolved to no location (a 0 hit count there proves nothing), and skips the
# SAMPLES. The SAMPLES values are read by hand (quickstart.md, "Read the output"). Exit 0 means the counts
# passed, not the samples. The lldb runs and checks are in probe-common.sh, shared with probe.sh.
# Only the app this script built is launched, attached to and stopped; other swiftSky processes are left
# alone. Nothing in the app changes; breakpoints slow the frame rate while attached.
set -euo pipefail

# hw.optional.arm64 is 1 on Apple silicon even when this shell runs under Rosetta.
[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] ||
  { echo "this probe reads arm64 registers; run it on Apple silicon" >&2; exit 2; }

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d)
APP="$WORK/dd/Build/Products/Debug/swiftSky.app"
BIN="$APP/Contents/MacOS/swiftSky"
trap 'pkill -f "$BIN" 2>/dev/null || true; rm -rf "$WORK"' EXIT
# shellcheck source=probe-common.sh
. "$HERE/probe-common.sh"

xcodebuild -project "$ROOT/swiftSky.xcodeproj" -scheme "swiftSky (macOS)" -configuration Debug \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$WORK/dd" build -quiet

# `open -n` brings the window to the front: a covered window pauses the frame loop. Keep it uncovered.
# The app is found by its executable's full path, which is unique to this run's scratch directory.
launch() {
  pkill -f "$BIN" 2>/dev/null || true
  sleep 1
  open -n "$APP" --args --no-ship --no-debug-overlay || return 1
  sleep 4
  pgrep -nf "$BIN"
}

# errexit does not reach inside $( ), so a failed launch is caught here.
launch_pid() {
  local pid
  pid=$(launch) || pid=
  [[ $pid =~ ^[0-9]+$ ]] || { echo "FAIL: the app did not launch" >&2; exit 1; }
  echo "$pid"
}

echo "=== xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "=== mac: $(sw_vers -productVersion) $(uname -m)"

echo "=== COUNTS"
PID=$(launch_pid)
run_counts "$PID"
counts_verdict

echo "=== SAMPLES"
# The encoder the call reaches is the GPU driver's, a different class per Mac model (AGXG13XFamilyRenderContext
# on an M1 Pro); the debug layer's classes sit beside it in the same pattern. The first hit on the frame-loop
# thread is the one sampled.
PID=$(launch_pid)
run_samples "$PID" '[A-Za-z0-9_]+'

echo "=== COUNTS PASSED; read the SAMPLES against quickstart.md"
