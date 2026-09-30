# Contract: Ship Sprite

**Feature**: `007-ship-sprite-rendering` | **Spec**: [../spec.md](../spec.md)

The rendering layer's new API and the guarantees the tests check. Internal types are `internal`, and
the tests reach them with `@testable import SwiftSkyRendering`, as for text.

## ShipSpritePlacement

```swift
struct ShipSpritePlacement: Equatable {
    init?(position: Vector2, heading: Double, surface: RenderSurface)
    let centrePixels: Vector2
    let topLeft: Vector2, topRight: Vector2, bottomLeft: Vector2, bottomRight: Vector2   // surface pixels, +y down
    var clipCorners: (Vector2, Vector2, Vector2, Vector2)  // bottom-left, bottom-right, top-left, top-right
}
```

With `s` the backing scale, W × H the surface in pixels, `v = Camera(surface:)!.view(fromWorld: position)`
and `k = GameSpace.shipLength / 2 · s`:

- `centrePixels = ((v.x·s).rounded(), (v.y·s).rounded())`, schoolbook rounding
- `f = (cos heading, −sin heading)`, `r = (sin heading, cos heading)`
- `topLeft = c + k·f − k·r`, `topRight = c + k·f + k·r`, `bottomLeft = c − k·f − k·r`,
  `bottomRight = c − k·f + k·r`
- clip of a pixel point p: `(p.x / W · 2 − 1, 1 − p.y / H · 2)`

| # | Guarantee | Spec |
|---|-----------|------|
| C1 | `nil` exactly when `Camera(surface:)` is `nil` | FR-012 |
| C2 | At heading 0, the image's top edge (`topLeft`→`topRight`) is the right-hand edge: both have x = c.x + k | FR-007, US2-1 |
| C3 | At +π/2 the top edge is at the top (smallest y); at π it is on the left; at −π/2 at the bottom | FR-007, US2-2 |
| C4 | For every heading, the four sides are 2k long and the corners are at right angles, each within 1e-6 (points, radians) | FR-008, SC-002, SC-003 |
| C5 | `centrePixels` has whole-number coordinates, is within half a pixel of `v·s`, and equals the mean of the corners | FR-006a, SC-003 |
| C6 | At quarter-turn headings, every corner is within 1e-9 of a whole pixel | FR-010 |
| C7 | For the same size in points, `v` (the unsnapped centre in points) and the side length in points (2k / s = 40) are identical at 1×, 2× and 3× | FR-008, SC-003 |
| C8 | The ship at the origin sits at the surface's centre (snapped) on wide, tall and 1,001 × 667-point surfaces | US1-1, US3-1 |
| C9 | Headings π and the next double above −π give corners within 1e-9 pixels of each other | Edge case: wrap |
| C10 | Clip corners of a ship at the origin are symmetric about (0, 0) when the centre needs no snapping | FR-006 |

## ShipImageBitmap

```swift
struct ShipImageBitmap {
    static let sizePixels = 80
    static var bundledURL: URL? { get }
    init(contentsOf url: URL) throws(ShipImageError)
    let widthPixels: Int, heightPixels: Int
    let bytes: [UInt8]   // RGBA, premultiplied, sRGB-encoded, top row first
}
enum ShipImageError: Error, Equatable { case missing, undecodable, wrongSize(width: Int, height: Int) }
```

| # | Guarantee | Spec |
|---|-----------|------|
| C11 | `bundledURL` exists, and the bundled file decodes to 80 × 80 with 25,600 bytes | FR-002, FR-003 |
| C12 | Every colour byte ≤ its pixel's alpha byte (premultiplied); some pixels have alpha 0, and some have alpha 255 | FR-004 |
| C13 | A URL with no file throws `missing`; a file that is not an image throws `undecodable`; a decodable image that is not 80 × 80 throws `wrongSize` | FR-005 |

## RendererError

| # | Guarantee | Spec |
|---|-----------|------|
| C14 | `.shipImageUnavailable(reason:)` has `diagnosticCode == "ship_image_unavailable"` for any reason, and its `userFacingDescription` mentions the ship image | FR-005, SC-006 |

## Renderer (behaviour; visual, not unit-tested)

- `init` builds `ShipSprite` after the quad, and throws `.shipImageUnavailable` on any failure of the
  image path.
- `render` encodes, in one pass: the quad; then, when `ShipSpritePlacement` exists (and, in
  Debug/Profiling, `drawsShip` is true), the ship; then text (FR-009).
- `#if SWIFTSKY_INSTRUMENTATION public var drawsShip: Bool = true`.

## Shaders

- `swiftsky_sprite_vertex(vertex_id, constant float2 *corners [[buffer(0)]])`: position
  `corners[vid]`; texture coordinate `(vid & 1, 1 − (vid >> 1))` (strip order bottom-left,
  bottom-right, top-left, top-right; the image's top row is v = 0).
- `swiftsky_sprite_fragment`: `texture2d<float> [[texture(0)]]`, `constexpr sampler(filter::linear,
  mip_filter::linear, address::clamp_to_zero)`; returns the sample as-is (premultiplied).

## Platform (Debug/Profiling only)

| # | Guarantee | Spec |
|---|-----------|------|
| C15 | `DebugShipOptions(arguments:)`: `--debug-ship-spin` sets `spins`; `--no-ship` sets `hidesShip`; the two are independent and unaffected by the text arguments; no argument sets neither | FR-013, FR-014 |
| C16 | With `debugShipSpin`, every frame advances with `ControlInput(thrust: 0, turn: 1)`; otherwise the loop is unchanged | FR-013 |
| C17 | No symbol or string for either switch exists in a Release binary | FR-015 |
