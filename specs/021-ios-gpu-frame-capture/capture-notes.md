# Capture notes: iOS GPU Frame Capture Check (SKY-18)

Filled from the output of [probe.sh](probe.sh), following [quickstart.md](quickstart.md). Fields and
expected values are in [data-model.md](data-model.md) "Probe run". Text only; nothing else is committed.

## Header

- T001 verify result (`./Scripts/verify.sh`, branch `021-ios-gpu-frame-capture`, 2026-10-18): VERIFICATION PASSED, all stages green (exit 0)
- Date of run: 2026-10-18
- Xcode version: Xcode 27.0, build version 27A266a
- Build: Debug (built by probe.sh, scheme `swiftSky (iOS)`) (expected: Debug)
- Launch arguments: `--no-ship --no-debug-overlay` (expected: `--no-ship --no-debug-overlay`)
- Simulator (model, UDID, OS): iPhone 18 Pro, 17791BD4-BD96-45F0-B617-A325459BD30A, iOS 27.0
- Failure notice shown at launch (yes/no): no — the renderer encoded and presented frames throughout (186 presents in 10 s); the failure notice replaces the surface, so no frames would be drawn

## Counts (10 s)

- presents: 186
- draws: 187
- pipeline bindings: 187
- viewport changes: 0
- pipeline-state creations: 0
- buffer creations: 0

## Sample 1

- thread: #7, tid 0x40864c9, `com.swiftsky.frameLoop`
- pipeline address, label: 0x00000001041af180, `swiftSky.fullscreenQuad`
- vertex buffer address, label, offset, index, length: 0x00000001041af0c0, `swiftSky.quadVertices`, 0, 0, 32
- vertex buffer floats: -1 -1 1 -1 -1 1 1 1
- draw primitive type, start, count: 4 (triangle strip), 0, 4

## Sample 2 (5 s later, same run)

- thread: #7, tid 0x40864c9, `com.swiftsky.frameLoop`
- pipeline address, label: 0x00000001041af180, `swiftSky.fullscreenQuad`
- vertex buffer address, label, offset, index, length: 0x00000001041af0c0, `swiftSky.quadVertices`, 0, 0, 32
- vertex buffer floats: -1 -1 1 -1 -1 1 1 1
- draw primitive type, start, count: 4 (triangle strip), 0, 4
- same pipeline and buffer addresses as sample 1: yes (0x00000001041af180 and 0x00000001041af0c0 in both)

## Re-run with the counts check (2026-10-18)

`probe.sh` after it learned to check its own counts and print `=== TOTALS`; same simulator, Xcode and
launch arguments. Exit 0, `=== COUNTS PASSED`.

| Breakpoint | Locations (all resolved) | Hits over 10 s |
|------------|--------------------------|----------------|
| `pipeline_new` | 27 | 0 |
| `buffer_new` | 45 | 0 |
| `set_viewport` | 8 | 0 |
| `set_pipeline` | 14 | 191 |
| `draw` | 7 | 191 |
| `present` | 4 | 190 |

Both samples again bound `swiftSky.fullscreenQuad` and `swiftSky.quadVertices` (offset 0, index 0,
32 bytes, `-1 -1 1 -1 -1 1 1 1`), drew 4, 0, 4, and had equal addresses (new launch, so new addresses:
0x00000001045a3180 and 0x00000001045a30c0).

## macOS (SKY-19, 2026-11-03)

[probe-macos.sh](probe-macos.sh), the macOS twin of `probe.sh`: MacBook Pro 18,1 (Apple M1 Pro), macOS 26.7,
Xcode 27.0 (27A266a); Debug build, scheme `swiftSky (macOS)`, launched with `open -n` and
`--no-ship --no-debug-overlay`. Exit 0, `=== COUNTS PASSED`. The window was uncovered throughout.

| Breakpoint | Locations (all resolved) | Hits over 10 s |
|------------|--------------------------|----------------|
| `pipeline_new` | 63 | 0 |
| `buffer_new` | 63 | 0 |
| `set_viewport` | 17 | 0 |
| `set_pipeline` | 23 | 394 |
| `draw` | 16 | 394 |
| `present` | 4 | 394 |

Samples, 5 s apart in one launch, on thread `com.swiftsky.frameLoop`: pipeline `swiftSky.fullscreenQuad`
at 0x0000000c874b0e00, vertex buffer `swiftSky.quadVertices` at 0x0000000c877d32c0 (offset 0, index 0, length
32, `-1 -1 1 -1 -1 1 1 1`), draw 4 (triangle strip), 0, 4. Both samples have the same addresses.

Differences from iOS: the call lands on the GPU driver's encoder, `AGXG13XFamilyRenderContext`, not
`MTLSerializerRenderCommandEncoder`, so the SAMPLES breakpoints use any class name; attaching to the running
app needed no permission prompt. The debug layer's classes sit beside the driver's in the same patterns, and
only one layer is hit per call (counts equal presents). 394 presents in 10 s is about 39 frames a second:
the breakpoints slow the loop, as on iOS.
