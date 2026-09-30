# Data Model: Ship Sprite Rendering

**Feature**: `007-ship-sprite-rendering` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

No persistent data. The entities below are in-memory values and one GPU resource set.

## Ship pose (existing, read-only here)

Carried by `SimulationState.ship` (004). The renderer reads two fields and writes none (FR-001).

| Field | Type | Meaning |
|-------|------|---------|
| `position` | `Vector2` | World units, +x right, +y up |
| `heading` | `Double` | Radians in (−π, π], 0 along +x, counter-clockwise positive |

No new fields are added to `SimulationState` or `Ship` (spec Assumptions: the pose is already there).

## ShipImageBitmap (new, rendering layer, CPU)

The decoded ship image, ready to upload. Built once at renderer initialisation (FR-003).

| Field | Type | Rule |
|-------|------|------|
| `widthPixels`, `heightPixels` | `Int` | Both exactly 80; otherwise decoding throws `wrongSize` |
| `bytes` | `[UInt8]` | 80 × 80 × 4, RGBA, row-major, top row first, sRGB-encoded, premultiplied: each colour byte ≤ its alpha byte |

Static `bundledURL: URL?` is the copy in the rendering layer's resource bundle (research R1).

**ShipImageError**: `missing` (no file at the URL), `undecodable` (not an image), `wrongSize(width:height:)`.

## ShipSpritePlacement (new, rendering layer, pure)

Where the ship is drawn for one pose on one surface. Built every frame; a plain value and never
allocates (FR-011). `init?(position:heading:surface:)` is `nil` when `Camera(surface:)` is `nil`
(FR-012). The formulas are in [contracts/ship-sprite.md](./contracts/ship-sprite.md).

| Field | Type | Meaning |
|-------|------|---------|
| `centrePixels` | `Vector2` | Drawn centre, in whole surface pixels from the top-left, +y down (FR-006a) |
| `topLeft`, `topRight`, `bottomLeft`, `bottomRight` | `Vector2` | The image's corners in surface pixels, +y down; named by their place in the image, not on screen |
| `clipCorners` | 4 × `Vector2` | The same corners in clip space, triangle-strip order: bottom-left, bottom-right, top-left, top-right |

Invariants: all four sides are `GameSpace.shipLength · backingScale` pixels long and meet at right
angles; the centre is the corners' mean; `topLeft − bottomLeft` points along the heading.

## ShipSprite (new, rendering layer, GPU)

Built once in `Renderer.init` and reused every frame (FR-011).

| Part | What |
|------|------|
| `pipelineState` | `swiftsky_sprite_vertex` / `swiftsky_sprite_fragment`, surface pixel format, blending `one` / `oneMinusSourceAlpha` |
| `texture` | 80 × 80 `.rgba8Unorm_srgb`, 7 mip levels, `.shaderRead`, level 0 from `ShipImageBitmap`, the rest from one blit at init |

The per-frame input is `ShipSpritePlacement.clipCorners`, sent as 4 × `SIMD2<Float>` (32 bytes) with
`setVertexBytes` at index 0.

## RendererError (extended)

| New case | Code | When |
|----------|------|------|
| `shipImageUnavailable(reason: String)` | `ship_image_unavailable` | Image missing, undecodable, wrong size, or it could not be put in graphics memory (FR-005) |

## DebugShipOptions (new, platform layer, Debug/Profiling only)

| Field | Launch argument | Effect |
|-------|-----------------|--------|
| `spins` | `--debug-ship-spin` | `FrameLoop.debugShipSpin = true`: every tick gets `ControlInput(thrust: 0, turn: 1)` (FR-013) |
| `hidesShip` | `--no-ship` | `Renderer.drawsShip = false` (FR-014) |

The two are independent of each other and of `DebugTextMode`. The type, both properties and both
strings are compiled out of Release (FR-015).
