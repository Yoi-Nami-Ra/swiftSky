# Quickstart: GPU Frame Capture Check (iOS; macOS by SKY-19)

The procedure for 001's checks 4 and 5 on iOS, and on macOS (SKY-19). It runs unattended in under 10
minutes. What each observation proves is in [research.md](research.md) R2 and R3; the fields and expected
values are in [data-model.md](data-model.md).

## Run

```bash
specs/021-ios-gpu-frame-capture/probe.sh
```

It uses the first booted simulator (pass a UDID to choose another), builds the Debug iOS app, launches
it with `--no-ship --no-debug-overlay`, attaches lldb and prints two parts.

On macOS (SKY-19), on Apple silicon, run its twin instead:

```bash
specs/021-ios-gpu-frame-capture/probe-macos.sh
```

It builds the Debug macOS app, launches it with `open -n` and the same arguments, and prints the same two
parts, read the same way below. Keep its window uncovered while it runs. The calls land on the GPU
driver's encoder (`AGXG13XFamilyRenderContext` on an M1 Pro), so its samples match any encoder class
on the frame-loop thread. Both probes share their lldb runs and checks, in `probe-common.sh`.

## Read the output

**COUNTS** (10 s, auto-continue breakpoints; non-zero locations and any backtraces, then `=== TOTALS`
with one `name locations hits` line per breakpoint):

- every breakpoint has at least one location. A breakpoint that resolved to nothing shows `0` locations
  and `-1` hits, and its 0 proves nothing;
- `present`, `draw` and `set_pipeline` hit counts above 0 and within one of each other: one quad draw
  per frame.
- `set_viewport` hit count 0: the default viewport, the whole drawable, is used.
- `pipeline_new` and `buffer_new` hit counts 0: nothing is created while frames run. Any hit prints a
  backtrace; name the caller in the record.

The probe checks these itself: it prints a `FAIL:` line for each one that does not hold and exits 1
before the samples (also when the app does not launch). Exit 0 means the counts passed; the samples are read by hand.

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

The probe exits 1 (`FAIL: … resolved to no location (or lldb did not attach)`). If the SAMPLES part
hangs, no frame is being encoded: the simulator window (on macOS, the app's window) is covered or the
failure notice is shown.
Stop and report it. The fallback is the hand capture in Xcode's GPU debugger (Debug navigator ›
Capture GPU Workload), which the developer decides on.
