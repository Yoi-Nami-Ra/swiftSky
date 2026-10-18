# Quickstart: iOS GPU Frame Capture Check

The procedure for 001's checks 4 and 5 on iOS. It runs unattended in under 10 minutes. What each
observation proves is in [research.md](research.md) R2 and R3; the fields and expected values are in
[data-model.md](data-model.md).

## Run

```bash
specs/021-ios-gpu-frame-capture/probe.sh
```

It uses the first booted simulator (pass a UDID to choose another), builds the Debug iOS app, launches
it with `--no-ship --no-debug-overlay`, attaches lldb and prints two parts.

## Read the output

**COUNTS** (10 s, auto-continue breakpoints; only non-zero locations are listed, plus the six totals):

- `present`, `draw` and `set_pipeline` hit counts within one of each other: one quad draw per frame.
- `set_viewport` hit count 0: the default viewport, the whole drawable, is used.
- `pipeline_new` and `buffer_new` hit counts 0: nothing is created while frames run. Any hit prints a
  backtrace; name the caller in the record.

**SAMPLES** (two, 5 s apart, on thread `com.swiftsky.frameLoop`):

- pipeline: an address and `swiftSky.fullscreenQuad`;
- vertex buffer: an address, `swiftSky.quadVertices`, offset 0, index 0, length 32, floats
  `-1 -1 1 -1 -1 1 1 1`;
- draw: `4` (triangle strip), `0`, `4`;
- the two samples' pipeline and buffer addresses are equal.

Check 4 passes on the counts' first two bullets and every sample value; check 5 on the counts' third
bullet and the equal addresses. Anything else is a FAIL: record what was seen and file a bug ticket.

## Record

Copy the observed values into `capture-notes.md`, then write the check records into
`specs/001-metal-app-shell/quickstart.md` and update its open-checks summary (spec FR-005, FR-006).

## Repository check

```bash
./Scripts/verify.sh
```

It must still pass; the feature changes no code.

## If lldb cannot attach or break

Stop and report it. The fallback is the hand capture in Xcode's GPU debugger (Debug navigator ›
Capture GPU Workload), which the developer decides on.
