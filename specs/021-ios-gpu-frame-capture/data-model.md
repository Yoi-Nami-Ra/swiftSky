# Data Model: iOS GPU Frame Capture Check

No code entities. Two records describe what the feature reads and writes.

## Probe run (read from `probe.sh` output, or `probe-macos.sh` on macOS since SKY-19; summarised in capture-notes.md)

| Field | From | Check | Expected |
|-------|------|-------|----------|
| Breakpoint locations | COUNTS, `=== TOTALS` | 4, 5 | ≥ 1 for each of the six (a 0 hit count on no location proves nothing) |
| Presents over 10 s | COUNTS, `presentDrawable:` hit count | 4 | > 0 (the frame count) |
| Draws over 10 s | COUNTS, `drawPrimitives:vertexStart:vertexCount:` | 4 | presents ± 1 |
| Pipeline bindings over 10 s | COUNTS, `setRenderPipelineState:` | 4 | presents ± 1 |
| Viewport changes | COUNTS, `setViewport:` | 4 | 0 |
| Pipeline-state creations | COUNTS, `newRenderPipelineStateWithDescriptor:…` | 5 | 0 |
| Buffer creations | COUNTS, `newBufferWith…` | 5 | 0 |
| Bound pipeline: address, label | SAMPLES 1 and 2 | 4, 5 | `swiftSky.fullscreenQuad`; same address in both |
| Bound vertex buffer: address, label, index, offset, length, contents | SAMPLES 1 and 2 | 4, 5 | `swiftSky.quadVertices`, index 0, offset 0, 32 bytes, (−1,−1) (1,−1) (−1,1) (1,1); same address in both |
| Draw: primitive type, start, count | SAMPLES 1 and 2 | 4 | 4 (triangle strip), 0, 4 |
| Thread | SAMPLES | — | `com.swiftsky.frameLoop` |

## Check record (written, in specs/001-metal-app-shell/quickstart.md)

One paragraph per check, under that check: in the "Visible output" section, after the records already
there, in the shape 001 already uses:

- heading line: `**Check N — PASS|FAIL on iOS, simulator (YYYY-MM-DD, SKY-18).**`
- build and destination: Xcode version, Debug, launch arguments, simulator model and OS
- method: lldb attached to the running app, by `specs/021-ios-gpu-frame-capture/probe.sh` following this
  feature's quickstart, instead of the GPU debugger, and why that settles the check
- what was observed, field by field from the table above
- on FAIL: the bug ticket's key

Plus two edits to the summary at the end of the file: the open-checks table's rows for 4 and 5 say
macOS only (SKY-19), or are removed if SKY-19 has recorded its half; and a dated sentence above the
table records that the iOS half closed.
