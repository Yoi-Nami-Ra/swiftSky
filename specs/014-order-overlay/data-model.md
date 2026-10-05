# Data Model: Draw the Order Overlay

All values are plain, fixed-size and allocation-free. Nothing here is stored between frames.

## Logic layer (`SwiftSkySimulation`)

### `PlannedPath` (changed, 010)

| Addition | Type | Meaning |
|----------|------|---------|
| `tick(ofPoint:)` | `(Int) -> UInt64` | The tick of point `index`: `startTick + index × spacing` for `index < count − 1`, `endTick` for the last point. Traps outside `0..<count`, like the subscript. |

Rule: ticks are strictly increasing along the path (the last point's tick is after the one before it,
since a point is kept only when due or at the end of the flight).

## Rendering layer (`SwiftSkyRendering`)

### `OrderOverlayStyle` (new)

Constants only (research R7). Sizes in points; the colour once, as linear premultiplied RGBA.

| Constant | Value |
|----------|-------|
| `markerRadius` | 7 pt to the stroke's centre (outer edge 8 pt) |
| `markerStroke` | 2 pt |
| `highlightRadius` | 28 pt |
| `highlightStroke` | 1.5 pt |
| `lineWidth` | 1.5 pt |
| `colour` | sRGB (0.35, 0.95, 0.80) at 85 %, premultiplied, linear |

### `OrderOverlay` (new)

What one frame draws of the current order (spec Key Entities), in surface pixels, +y down.

| Field | Type | Meaning |
|-------|------|---------|
| `linePoints` | `InlineArray<258, Vector2>` | The line: drawn ship position, the remaining path points, the destination. Slots past `lineCount` are unused. |
| `lineCount` | `Int` | 2…258. |
| `markerCentre` | `Vector2` | The destination in pixels, unrounded. Always `linePoints[lineCount − 1]`. |
| `highlightCentre` | `Vector2` | The sprite's whole-pixel centre (`ShipSpritePlacement.centrePixels`). |
| `scale` | `Double` | The surface's backing scale: points → pixels for every size. |
| `surfaceWidthPixels`, `surfaceHeightPixels` | `Double` | For pixels → clip space in the shader. |

`init?(state:shipPose:poseTick:surface:)` returns `nil` (draw nothing) when any of these holds:
- `state.autopilot.order == nil`;
- `state.autopilot.phase == .arrived`;
- `state.plannedPath.isEmpty`;
- the surface has no camera (005).

Otherwise:
1. `linePoints[0]` = camera view of `shipPose.position` × scale.
2. For each path index `i` in order with `tick(ofPoint: i) > poseTick`: append its view × scale.
3. Append the order's destination's view × scale; that is `markerCentre`.
4. `highlightCentre` = `ShipSpritePlacement(position: shipPose.position, heading: shipPose.heading,
   surface:).centrePixels`.

Equality: two overlays are equal when their fields and their first `lineCount` points are.

### GPU records (shader side, `Shaders.metal`)

| Record | Layout | Use |
|--------|--------|-----|
| `OverlayUniforms` | `float2 surfacePixels; float lineHalfWidth; float pad;` | Both draws. |
| line points | `float2[lineCount]` | Line draw: instance `i` is the segment `points[i] → points[i + 1]`. |
| `OverlayRing` | `float2 centre; float radius; float halfWidth;` (16 bytes) | Ring draw: two instances, marker and highlight. |

`lineHalfWidth`, ring radii and half widths are in pixels: the style's points × scale.

## Platform layer (`SwiftSkyPlatform`)

### `FrameLoop` (changed)

Computes `poseTick` beside the drawn pose (research R2) and passes it to `render`. Holds nothing new.

## State transitions

The overlay has no state of its own. Its visibility follows the autopilot:

```text
no order ──order──▶ flying (aligning/burning/flipping/braking) ──arrival──▶ arrived
   ▲  hidden              shown                                   │ hidden
   │                       ▲  new order: replaced                  │
   └───────────────────────┴──────── new order / leaves tolerance ─┘
```
