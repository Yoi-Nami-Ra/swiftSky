# Contract: Order Overlay

Internal contracts between the layers for 014. Clause numbers are referenced by tasks and tests.

## C1 — `PlannedPath.tick(ofPoint:)` (logic layer)

- For `0 ≤ index < count − 1`: returns `startTick + UInt64(index × spacing)`.
- For `index == count − 1`: returns `endTick`.
- Ticks increase strictly with `index`.
- Precondition: `0 ≤ index < count`.
- Pure, allocation-free.

## C2 — `OrderOverlay.init?(state:shipPose:poseTick:surface:)` (rendering layer)

- `nil` when there is no order, the phase is `.arrived`, the path is empty, or `Camera(surface:)` is
  `nil` (FR-001, FR-015).
- Otherwise: `linePoints[0]` is the drawn ship position in pixels; then the path points with
  `tick(ofPoint:) > poseTick`, in order; last the destination, which equals `markerCentre` (FR-006,
  FR-007, SC-002).
- `markerCentre` is the destination through `Camera.view(fromWorld:)` × backing scale, unrounded
  (FR-011, SC-001).
- `highlightCentre` equals `ShipSpritePlacement(position: shipPose.position, heading:
  shipPose.heading, surface: surface)!.centrePixels` (FR-005).
- Reads only its arguments; changes nothing (FR-016). Pure, allocation-free, deterministic.

## C3 — `Renderer.render(state:shipPose:poseTick:surface:drawable:timestamp:)`

- `poseTick` (new): the latest tick at or behind `shipPose`. Used only to decide which path points are
  reached (C2).
- Draw order in the one pass: background quad, order overlay (when C2 gives one), ship sprite, text
  (FR-009).
- The overlay is drawn in every build configuration (FR-003); `drawsShip == false` skips only the
  sprite.
- Allocation-free per frame: two pipeline states built in `init`; data passed with `setVertexBytes`
  (FR-013).

## C4 — `poseTick` in `FrameLoop`

- Interpolating: `tickCount − 1`, or 0 when `tickCount == 0`.
- `--no-interpolation`: `tickCount`.
- Computed from the same `interpolates` flag as the drawn pose, so they never disagree (FR-012).

## C5 — Shaders

- `swiftsky_overlay_line_vertex`: instance `i` draws the segment `points[i] → points[i + 1]` as a quad
  grown by `lineHalfWidth + 1` pixel on every side.
- `swiftsky_overlay_ring_vertex`: instance `i` draws ring `i` as a square of half side
  `radius + halfWidth + 1` pixels.
- `swiftsky_overlay_fragment`: coverage `clamp(halfWidth + 0.5 − |d − radius|, 0, 1)` with `d` the
  pixel centre's distance to the segment (`radius = 0` for lines); returns the style colour × coverage,
  premultiplied.
- Blending: operation `max`, factors `one`/`one` (research R5).
