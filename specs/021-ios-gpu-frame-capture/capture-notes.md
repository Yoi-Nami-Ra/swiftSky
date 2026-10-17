# Capture notes: iOS GPU Frame Capture Check (SKY-18)

Filled in by the developer while following [quickstart.md](quickstart.md). Fields are described in
[data-model.md](data-model.md) "Captured frame". Screenshots are not committed.

## Header

- T001 verify result (`./Scripts/verify.sh`, branch `021-ios-gpu-frame-capture`, 2026-10-18): VERIFICATION PASSED, all stages green (exit 0)
- Date of capture: _(to fill)_
- Xcode version: _(to fill)_
- Build: _(to fill)_ (expected: Debug)
- Launch arguments: _(to fill)_ (expected: `--no-ship --no-debug-overlay`)
- Destination (simulator or device, model, OS): _(to fill)_
- Failure notice shown at launch (yes/no): _(to fill)_

## Check 4 — the quad draw covers the surface (capture 1)

### Draws in the render pass
_(to fill)_

### Draw's pipeline label
_(to fill)_ (expected: `swiftSky.fullscreenQuad`)

### Draw's vertex buffer label
_(to fill)_ (expected: `swiftSky.quadVertices`)

### Geometry (primitive, vertex count, positions)
_(to fill)_ (expected: triangle strip, 4 vertices, (−1, −1) … (1, 1))

### Pixel history (the quad draw listed for each pixel?)
- Corner 1 (top-left): _(to fill)_
- Corner 2 (top-right): _(to fill)_
- Corner 3 (bottom-left): _(to fill)_
- Corner 4 (bottom-right): _(to fill)_
- Centre: _(to fill)_

## Check 5 — built once, reused

### Creation calls inside the frame
- Capture 1 (pipeline state or buffer creation calls): _(to fill)_
- Capture 2, taken at least 5 s later: _(to fill)_

### Object identity of pipeline and buffer
- Capture 1 (count of each by label; identity): _(to fill)_
- Capture 2 (count of each by label; identity): _(to fill)_
- Same identity across both captures: _(to fill)_

## Optional — default launch

_(to fill)_ (arguments removed; expect quad draw first, then ship and debug overlay draws)
