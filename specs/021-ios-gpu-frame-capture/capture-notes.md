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
