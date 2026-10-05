# Research: Draw the Order Overlay

Decision record for [plan.md](./plan.md). Each entry: decision, rationale, alternatives considered.

## R1 — One prepared value per frame, pure and tested

**Decision**: `OrderOverlay`, a rendering-layer value built every frame by
`OrderOverlay(state:shipPose:poseTick:surface:)`. It returns `nil` when nothing is drawn (no order,
arrived, empty path, no camera), and otherwise holds everything the GPU needs in surface pixels: the
line's points, the marker's centre and the highlight's centre, plus the surface size. The encoder only copies
it into the command stream.

**Rationale**: the same split as `ShipSpritePlacement` (007 R5): what the tests check is exactly what is
drawn, and the placement maths runs headlessly with no Metal device (Principle II, FR-017). Being a
value built from the state each frame, it keeps nothing between frames, so a new order or an arrival
shows on the next frame with no bookkeeping (FR-002).

**Alternatives considered**:
- *Compute in the shader from the raw path*: untestable without a GPU, and the reached-point rule and
  the camera would be duplicated in Metal.
- *Keep the overlay in the simulation state*: the overlay is presentation; the logic layer must not
  know about pixels (Principle I).

## R2 — Which points are reached: the pose tick

**Decision**: the renderer gets one more argument, `poseTick`: the latest tick at or behind the drawn
pose. The frame loop computes it next to the drawn pose: `tickCount − 1` when interpolating (the drawn
pose blends ticks `tickCount − 1` and `tickCount`), `tickCount` under `--no-interpolation`, and 0 before
any tick. A predicted point is reached when its tick is ≤ `poseTick` (spec FR-007, clarification Q1).
The logic layer gains `PlannedPath.tick(ofPoint:)`: `startTick + index × spacing` for every point but the
last, and `endTick` for the last, which may fall off the spacing grid when the prediction stopped
between two due points (010 R7).

**Rationale**: only the frame loop knows whether it interpolated; passing the tick keeps the renderer
free of that switch and of `TimeAccumulator`. The point's tick is a property of the path's own
bookkeeping, so it belongs, tested, in the logic layer beside it.

**Alternatives considered**:
- *Renderer subtracts one itself*: wrong under `--no-interpolation`, which 013 FR-008 says every
  consumer follows.
- *Nearest point by distance*: ambiguous where the path doubles back (turn-back orders) and costs a scan
  with comparisons; the tick is exact.

## R3 — The line: start, remaining points, destination

**Decision**: the line's points are, in order: the drawn ship position; every path point whose tick is
after `poseTick`; and the order's destination. The destination is always appended, even when the last
predicted point is within the arrival tolerance of it (a segment shorter than a pixel draws nothing
visible), so the line always ends exactly at the marker's centre, whether or not the prediction reached
arrival (FR-006). Capacity: 1 + 256 + 1 = 258 points, 257 segments.

**Rationale**: one rule covers arrival and the 60-second cap, and the end of the line is the marker's
centre by construction (SC-002).

**Alternatives considered**: *append the destination only when `reachesArrival` is false*: the arrived
end point is up to 1 unit (the position tolerance) off the destination, so the line would visibly stop
short of the marker's centre at 2× and 3×.

## R4 — Drawing thick, smooth lines and rings: one signed-distance fragment shader

**Decision**: one fragment shader draws both shapes from a distance field. Each primitive is a quad
covering a segment `p0 → p1` grown by its reach; the fragment computes the distance `d` from its pixel
centre to the segment and covers `clamp(halfWidth + 0.5 − |d − ringRadius|, 0, 1)` — a one-pixel
anti-aliased edge. A line segment has `ringRadius = 0` (a capsule); a ring has `p0 = p1` and
`ringRadius > 0`. Two vertex functions build the quads: one reads consecutive pairs from the line's
point array (instanced, one instance per segment), the other reads ring records. Two pipeline states,
built once, share the fragment function.

**Rationale**: 1.5-point lines need anti-aliasing, and the project has no MSAA; Metal's line primitive is
one pixel wide with no caps. A distance field gives exact widths in pixels at any scale (FR-010), round
joins for free, and the same code draws the rings. No tessellation on the CPU: the per-frame data is
only the points.

**Alternatives considered**:
- *CPU-tessellated triangle strips*: joins and anti-aliasing would need extra geometry per point (up to
  ~1,500 vertices), more code and more tests for a worse edge.
- *MSAA*: changes the whole pass and every existing pipeline for one overlay.

## R5 — Overlapping segments: blend with maximum

**Decision**: the overlay pipelines blend with operation `max` on premultiplied colour. The overlay is
drawn straight after the background, so it is drawn over black only.

**Rationale**: consecutive capsules overlap at every joint, and on a slow stretch of path the points are
less than a pixel apart, so dozens of capsules cover the same pixel. "Over" blending would build up
alpha there and draw bright beads along the line. With `max`, a pixel takes the strongest coverage of
any primitive, exactly what a single shape would give; over black, `max(c, 0)` equals "over", so the
result is the intended colour at the intended strength. The ship and text are drawn afterwards with
their own "over" blending, unchanged.

**Alternatives considered**:
- *Opaque colour*: avoids build-up but loses the softer, partly transparent look FR-008 asks for and
  any anti-aliasing (coverage would still need blending).
- *Stencil to draw each pixel once*: needs a stencil attachment the pass does not have.
- *Merge the path into one distance field*: a per-fragment loop over 257 segments.

**Limit**: correct only over a black background. A textured background (Assumptions) would need this
revisited; recorded in the spec's Assumptions.

## R6 — Passing the data: `setVertexBytes`, no buffers

**Decision**: the line's points go to the GPU as up to 258 `SIMD2<Float>` (2,064 bytes) with
`setVertexBytes`, the two rings as two 16-byte records, and one small uniforms record (surface size in
pixels, half widths). All are under the 4 KB `setVertexBytes` limit. They are written into a
fixed-size, stack-held `InlineArray` and copied into the command stream, as the ship's corners are
(007 R5).

**Rationale**: no `MTLBuffer` to create, reuse or synchronise with the GPU (the text ring's completion
tracking, 011 R13, is not needed), and no heap allocation per frame (FR-013, SC-005).

**Alternatives considered**: *a triple-buffered vertex buffer*: needs slot tracking for no gain at this
size.

## R7 — Style values in one place

**Decision**: `OrderOverlayStyle`, a namespace of constants: marker radius 8 pt and stroke 2 pt, ring
radius 28 pt and stroke 1.5 pt, line width 1.5 pt (spec FR-004–FR-006), and the colour: sRGB
(0.35, 0.95, 0.80), a cyan-green, at 85 % strength, premultiplied and converted to linear for the sRGB
surface on the CPU, once. Radii are to the stroke's centre, so the marker's outer edge is
8 pt = radius 7 + half stroke 1.

**Rationale**: no design exists (spec Assumptions); one place for a later design to change. The colour
is far from the ship's palette and reads clearly on black; on a black background 85 % strength is what
"partly transparent" means (R5).

**Alternatives considered**: *system accent colour*: lives in AppKit/UIKit, which the rendering layer
does not import, and can be any colour, including ones that vanish on black.

## R8 — Ring centre: the sprite's whole-pixel centre

**Decision**: the ring is centred on `ShipSpritePlacement(position:heading:surface:).centrePixels`, the
sprite's rounded centre (clarification Q2). The line's first point and the marker are not rounded.

**Rationale**: reusing the sprite's own placement makes ring and sprite agree by construction, and the
test is an equality.

## R9 — Draw order, builds and switches

**Decision**: encoded after the background quad and before the ship (FR-009), in every build (FR-003).
`--no-ship` (`drawsShip`) skips only the sprite. No new launch argument.

**Rationale**: the ship covers its own ring and the line's start, so the ship stays the clearest thing
on screen. No order exists at launch, so the black-surface checks of 001 and 002 are unaffected
(SC-004).
