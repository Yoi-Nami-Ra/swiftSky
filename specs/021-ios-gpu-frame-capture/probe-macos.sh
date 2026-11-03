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
# Then it checks the COUNTS: it exits 1 with a FAIL line for each count that breaks check 4 or 5, or for
# a breakpoint that resolved to no location (a 0 hit count there proves nothing). The SAMPLES values are
# read by hand (quickstart.md, "Read the output"). Exit 0 means the counts passed, not the samples.
# Nothing in the app changes; breakpoints slow the frame rate while attached.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
APP="$WORK/dd/Build/Products/Debug/swiftSky.app"
[ "$(uname -m)" = arm64 ] || { echo "this probe reads arm64 registers; run it on Apple silicon" >&2; exit 2; }

xcodebuild -project "$ROOT/swiftSky.xcodeproj" -scheme "swiftSky (macOS)" -configuration Debug \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$WORK/dd" build -quiet

# `open -n` brings the window to the front: a covered window pauses the frame loop. Keep it uncovered.
launch() {
  pkill -x swiftSky 2>/dev/null || true
  sleep 1
  open -n "$APP" --args --no-ship --no-debug-overlay || return 1
  sleep 4
  pgrep -nx swiftSky
}

# errexit does not reach inside $( ), so a failed launch is caught here.
launch_pid() {
  local pid
  pid=$(launch) || pid=
  [[ $pid =~ ^[0-9]+$ ]] || { echo "FAIL: the app did not launch" >&2; exit 1; }
  echo "$pid"
}

C='-\[[A-Za-z0-9_]+ '
echo "=== xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "=== mac: $(sw_vers -productVersion) $(uname -m)"

echo "=== COUNTS"
PID=$(launch_pid)
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
  -o "process detach" >"$WORK/counts.txt" 2>&1 || true
grep -E "^[0-9]+: regex|hit count|where = |frame #|error" "$WORK/counts.txt" | grep -v "hit count = 0 *$" || true

# One line per breakpoint from `breakpoint list`: its name, locations and hit count. A breakpoint that
# resolved to nothing prints "locations = 0 (pending)" and no hit count.
TOTALS=$(awk '
  /^[0-9]+: regex = / {
    id = $1; sub(":", "", id)
    loc[id] = 0; if (match($0, /locations = [0-9]+/)) loc[id] = substr($0, RSTART + 12, RLENGTH - 12) + 0
    hit[id] = -1; if (match($0, /hit count = [0-9]+/)) hit[id] = substr($0, RSTART + 12, RLENGTH - 12) + 0
    cur = id; next
  }
  /^  Names:$/ { getline; gsub(/ /, ""); name[cur] = $0 }
  END { for (i in name) print name[i], loc[i], hit[i] }
' "$WORK/counts.txt")
echo "=== TOTALS (name locations hits)"
echo "$TOTALS"

failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
total() { awk -v n="$1" -v f="$2" '$1 == n { print $f; found = 1 } END { if (!found) print -1 }' <<<"$TOTALS"; }
for name in pipeline_new buffer_new set_viewport set_pipeline draw present; do
  [ "$(total "$name" 2)" -ge 1 ] || fail "$name resolved to no location (or lldb did not attach)"
done
for name in pipeline_new buffer_new set_viewport; do
  [ "$(total "$name" 3)" -eq 0 ] || fail "$name hit $(total "$name" 3) times, expected 0"
done
present=$(total present 3)
[ "$present" -gt 0 ] || fail "no frame was presented"
for name in draw set_pipeline; do
  n=$(total "$name" 3)
  [ $((n - present)) -le 1 ] && [ $((present - n)) -le 1 ] || fail "$name hit $n times for $present presents"
done

echo "=== SAMPLES"
# The encoder the call reaches is the GPU driver's, a different class per Mac model (AGXG13XFamilyRenderContext
# on an M1 Pro); the debug layer's classes sit beside it in the same pattern. The first hit is the one sampled.
E='[A-Za-z0-9_]+'
SAMPLE=(
  -o "breakpoint set -o true -r \"^-\\[$E setRenderPipelineState:\\]\$\""
  -o "process continue" -o "thread info" -o 'p/x $x2' -o 'po [(id)$x2 label]'
  -o "breakpoint set -o true -r \"^-\\[$E setVertexBuffer:offset:atIndex:\\]\$\""
  -o "process continue" -o 'p/x $x2' -o 'po [(id)$x2 label]' -o 'p (unsigned long)$x3' -o 'p (unsigned long)$x4'
  -o 'p (unsigned long)[(id)$x2 length]' -o 'memory read -f f -s 4 -c 8 `(void*)[(id)$x2 contents]`'
  -o "breakpoint set -o true -r \"^-\\[$E drawPrimitives:vertexStart:vertexCount:\\]\$\""
  -o "process continue" -o 'p (unsigned long)$x2' -o 'p (unsigned long)$x3' -o 'p (unsigned long)$x4'
)
PID=$(launch_pid)
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

pkill -x swiftSky 2>/dev/null || true
rm -rf "$WORK"
[ "$failures" -eq 0 ] || { echo "=== COUNTS FAILED ($failures)"; exit 1; }
echo "=== COUNTS PASSED; read the SAMPLES against quickstart.md"
