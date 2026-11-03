# 021: the part of probe.sh (iOS simulator, SKY-18) and probe-macos.sh (SKY-19) that does not depend on the
# platform: the COUNTS lldb run and its pass/fail checks, and the SAMPLES lldb run. Sourced, not run;
# the caller sets WORK (a scratch directory) and has already launched the app.
# shellcheck shell=bash

C='-\[[A-Za-z0-9_]+ '

failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
total() { awk -v n="$1" -v f="$2" '$1 == n { print $f; found = 1 } END { if (!found) print -1 }' <<<"$TOTALS"; }

# run_counts PID: attaches to PID for 10 s, prints the COUNTS part and the TOTALS, and counts each check
# that does not hold in `failures`.
run_counts() {
  xcrun lldb --batch \
    -o "settings set target.process.stop-on-sharedlibrary-events false" \
    -o "process attach -p $1" \
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

  local name n present
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
}

# Exits 1 when a COUNTS check failed. Called before the SAMPLES: with no frames their one-shot
# breakpoints never fire and lldb would wait for ever.
counts_verdict() {
  [ "$failures" -eq 0 ] || { echo "=== COUNTS FAILED ($failures)"; exit 1; }
}

# run_samples PID ENCODER: two samples, 5 s apart, of the first pipeline binding, vertex buffer binding
# and draw on the frame-loop thread (com.swiftsky.frameLoop), on encoder classes matching the regex ENCODER.
run_samples() {
  local E=$2 T='-T com.swiftsky.frameLoop'
  local SAMPLE=(
    -o "breakpoint set -o true $T -r \"^-\\[$E setRenderPipelineState:\\]\$\""
    -o "process continue" -o "thread info" -o 'p/x $x2' -o 'po [(id)$x2 label]'
    -o "breakpoint set -o true $T -r \"^-\\[$E setVertexBuffer:offset:atIndex:\\]\$\""
    -o "process continue" -o 'p/x $x2' -o 'po [(id)$x2 label]' -o 'p (unsigned long)$x3' -o 'p (unsigned long)$x4'
    -o 'p (unsigned long)[(id)$x2 length]' -o 'memory read -f f -s 4 -c 8 `(void*)[(id)$x2 contents]`'
    -o "breakpoint set -o true $T -r \"^-\\[$E drawPrimitives:vertexStart:vertexCount:\\]\$\""
    -o "process continue" -o 'p (unsigned long)$x2' -o 'p (unsigned long)$x3' -o 'p (unsigned long)$x4'
  )
  xcrun lldb --batch \
    -o "settings set target.process.stop-on-sharedlibrary-events false" \
    -o "process attach -p $1" \
    -o 'script print("--- sample 1")' "${SAMPLE[@]}" \
    -o "script lldb.debugger.SetAsync(True)" -o "process continue" \
    -o "script import time; time.sleep(5)" -o "process interrupt" -o "script time.sleep(2)" \
    -o "script lldb.debugger.SetAsync(False)" \
    -o 'script print("--- sample 2")' "${SAMPLE[@]}" \
    -o "process detach" 2>&1 \
    | grep -vE "^ {4,}0x|^->|^\s*$|^(libsystem|Metal|MetalSerializer)\`" || true
}
