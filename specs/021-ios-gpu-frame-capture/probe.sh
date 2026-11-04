#!/bin/bash
# 021 (SKY-18): observe the iOS app's frames with lldb, for 001's checks 4 and 5.
#
# Usage: specs/021-ios-gpu-frame-capture/probe.sh [simulator-udid]
#   Builds the Debug iOS app, installs it on the simulator (booting it if needed), launches it with
#   --no-ship --no-debug-overlay, attaches lldb, and prints two parts:
#   1. COUNTS: hit counts over 10 s for draws, pipeline bindings, presents, viewport changes and
#      pipeline-state / buffer creation (creations and viewport changes print a backtrace).
#   2. SAMPLES: two samples, 5 s apart, of the bound pipeline, the bound vertex buffer (address, label,
#      length, contents as floats) and the draw's arguments (primitive type, start, count).
# After the COUNTS it checks them: it exits 1 with a FAIL line for each count that breaks check 4 or 5, or
# for a breakpoint that resolved to no location (a 0 hit count there proves nothing), and skips the
# SAMPLES. The SAMPLES values are read by hand (quickstart.md, "Read the output"). Exit 0 means the counts
# passed, not the samples. The lldb runs and checks are in probe-common.sh, shared with probe-macos.sh.
# Nothing in the app changes; breakpoints slow the frame rate while attached.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
UDID=${1:-$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1)}
[ -n "$UDID" ] || { echo "no booted simulator; pass a UDID" >&2; exit 2; }
xcrun simctl boot "$UDID" 2>/dev/null || true
BUNDLE=com.swiftsky.app
WORK=$(mktemp -d)
trap 'xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true; rm -rf "$WORK"' EXIT
# shellcheck source=SCRIPTDIR/probe-common.sh
. "$HERE/probe-common.sh"

xcodebuild -project "$ROOT/swiftSky.xcodeproj" -scheme "swiftSky (iOS)" -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$WORK/dd" build -quiet
xcrun simctl install "$UDID" "$WORK/dd/Build/Products/Debug-iphonesimulator/swiftSky.app"

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  local out
  out=$(xcrun simctl launch "$UDID" "$BUNDLE" --no-ship --no-debug-overlay) || return 1
  sleep 4
  echo "${out##*: }"
}


echo "=== xcode: $(xcodebuild -version | tr '\n' ' ')"
xcrun simctl list devices | grep "$UDID" | sed 's/^ */=== simulator: /'

echo "=== COUNTS"
PID=$(launch_pid)
run_counts "$PID"
counts_verdict

echo "=== SAMPLES"
run_samples "$PID" 'MTLSerializerRenderCommandEncoder'

echo "=== COUNTS PASSED; read the SAMPLES against quickstart.md"
