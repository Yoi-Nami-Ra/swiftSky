# Data Model: iOS GPU Frame Capture Check

No code entities. Two records describe what the feature reads and writes.

## Captured frame (read, in Xcode; not committed)

| Field | Read from | Check |
|-------|-----------|-------|
| Draws in the render pass | Debug navigator, call list | 4: the quad draw is there (only draw with ship/overlay off) |
| Draw's pipeline label | Draw's bound resources | 4, 5: `swiftSky.fullscreenQuad` |
| Draw's vertex buffer label | Draw's bound resources | 4, 5: `swiftSky.quadVertices` |
| Vertex count, primitive, positions | Geometry viewer | 4: 4, triangle strip, (−1, −1) … (1, 1) |
| Pixel history at 4 corners + centre | Attachment viewer | 4: the quad draw wrote each pixel |
| Creation calls inside the frame | Call list | 5: none for a pipeline state or buffer |
| Object identity of pipeline and buffer | Object inspector | 5: equal across the two captures |

## Check record (written, in specs/001-metal-app-shell/quickstart.md)

One paragraph per check, after the existing check records, in the shape 001 already uses:

- heading line: `**Check N — PASS|FAIL on iOS, simulator|device (YYYY-MM-DD, SKY-18).**`
- build and destination: Xcode version, Debug, launch arguments, simulator or device model and OS
- what was observed, field by field from the table above
- on FAIL: the bug ticket's key

Plus two edits to the summary at the end of the file: the open-checks table's rows for 4 and 5 say
macOS only (SKY-19), or are removed if SKY-19 has recorded its half; and the paragraph above the table
records that the iOS half closed.
