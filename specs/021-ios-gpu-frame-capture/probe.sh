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
# Nothing in the app changes; breakpoints slow the frame rate while attached.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
UDID=${1:-$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1)}
[ -n "$UDID" ] || { echo "no booted simulator; pass a UDID" >&2; exit 2; }
xcrun simctl boot "$UDID" 2>/dev/null || true
WORK=$(mktemp -d)
BUNDLE=com.swiftsky.app

xcodebuild -project "$ROOT/swiftSky.xcodeproj" -scheme "swiftSky (iOS)" -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$WORK/dd" build -quiet
xcrun simctl install "$UDID" "$WORK/dd/Build/Products/Debug-iphonesimulator/swiftSky.app"

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  local out
  out=$(xcrun simctl launch "$UDID" "$BUNDLE" --no-ship --no-debug-overlay)
  sleep 4
  echo "${out##*: }"
}

C='-\[[A-Za-z0-9_]+ '
echo "=== xcode: $(xcodebuild -version | tr '\n' ' ')"
xcrun simctl list devices | grep "$UDID" | sed 's/^ */=== simulator: /'

echo "=== COUNTS"
PID=$(launch)
xcrun lldb --batch \
  -o "settings set target.process.stop-on-sharedlibrary-events false" \
  -o "process attach -p $PID" \
  -o "breakpoint set -N pipeline_new -r \"^${C}newRenderPipelineStateWithDescriptor:\" -G true" \
  -o "breakpoint command add -o \"thread backtrace -c 8\" pipeline_new" \
  -o "breakpoint set -N buffer_new -r \"^${C}newBufferWith(Bytes|Length)\" -G true" \
  -o "breakpoint command add -o \"thread backtrace -c 8\" buffer_new" \
  -o "breakpoint set -N set_viewport -r \"^${C}setViewport:\\]\$\" -G true" \
  -o "breakpoint command add -o \"thread backtrace -c 4\" set_viewport" \
  -o "breakpoint set -N set_pipeline -r \"^${C}setRenderPipelineState:\\]\$\" -G true" \
  -o "breakpoint set -N draw -r \"^${C}drawPrimitives:vertexStart:vertexCount:\\]\$\" -G true" \
  -o "breakpoint set -N present -r \"^${C}presentDrawable:\\]\$\" -G true" \
  -o "script lldb.debugger.SetAsync(True)" \
  -o "process continue" \
  -o "script import time; time.sleep(10)" \
  -o "process interrupt" \
  -o "script time.sleep(2)" \
  -o "script lldb.debugger.SetAsync(False)" \
  -o "breakpoint list" \
  -o "process detach" 2>&1 \
  | grep -E "^[0-9]+: name|^[0-9]+: regex|hit count|where = |frame #|error" | grep -v "hit count = 0 *$" || true

echo "=== SAMPLES"
E='MTLSerializerRenderCommandEncoder'
SAMPLE=(
  -o "breakpoint set -o true -r \"^-\\[$E setRenderPipelineState:\\]\$\""
  -o "process continue" -o "thread info" -o 'p/x $x2' -o 'po [(id)$x2 label]'
  -o "breakpoint set -o true -r \"^-\\[$E setVertexBuffer:offset:atIndex:\\]\$\""
  -o "process continue" -o 'p/x $x2' -o 'po [(id)$x2 label]' -o 'p (unsigned long)$x3' -o 'p (unsigned long)$x4'
  -o 'p (unsigned long)[(id)$x2 length]' -o 'memory read -f f -s 4 -c 8 `(void*)[(id)$x2 contents]`'
  -o "breakpoint set -o true -r \"^-\\[$E drawPrimitives:vertexStart:vertexCount:\\]\$\""
  -o "process continue" -o 'p (unsigned long)$x2' -o 'p (unsigned long)$x3' -o 'p (unsigned long)$x4'
)
PID=$(launch)
xcrun lldb --batch \
  -o "settings set target.process.stop-on-sharedlibrary-events false" \
  -o "process attach -p $PID" \
  -o 'script print("--- sample 1")' "${SAMPLE[@]}" \
  -o "script lldb.debugger.SetAsync(True)" -o "process continue" \
  -o "script import time; time.sleep(5)" -o "process interrupt" -o "script time.sleep(2)" \
  -o "script lldb.debugger.SetAsync(False)" \
  -o 'script print("--- sample 2")' "${SAMPLE[@]}" \
  -o "process detach" 2>&1 \
  | grep -vE "^ {4,}0x|^->|^\s*$|^(libsystem|Metal|MetalSerializer)\`" || true

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
rm -rf "$WORK"
