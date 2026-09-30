# Data Model: Game Space and Camera

**Feature**: `005-game-space-camera` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

All values are `Sendable` structs or caseless enums in `SwiftSkyRendering`. No state changes over
time: a camera is built, used, and replaced.

## Spaces

| Space | Origin | Axes | Unit | Carried as |
|-------|--------|------|------|------------|
| World | the world origin, at the surface centre | +x right, +y up | world unit (= 1 point) | `Vector2` (logic layer) |
| View | the surface's top-left corner | +x right, +y **down** | point | `Vector2` |
| Normalised device coordinates (clip) | the surface centre | +x right, +y up | the surface's half-extent (edges at ±1) | `Vector2` |

## Camera

The fixed mapping between the world and one surface (spec FR-003…FR-008).

| Field | Type | Meaning | Invariant |
|-------|------|---------|-----------|
| `halfWidth` | `Double` (let) | w/2, half the surface width in points | normal (finite, not subnormal), > 0 |
| `halfHeight` | `Double` (let) | h/2, half the surface height in points | normal (finite, not subnormal), > 0 |
| `widthPoints` | `Double` (computed) | `2 × halfWidth` | — |
| `heightPoints` | `Double` (computed) | `2 × halfHeight` | — |

**Construction**: `init?(surface: RenderSurface)`.

- `nil` when `surface.isRenderable` is false (zero width or zero height) or `surface.backingScale` is
  not finite or not greater than zero (FR-008), or when a resulting half-extent is not a normal
  number (an extreme scale overflowing to ∞ or underflowing to a subnormal).
- Otherwise `halfWidth = Double(widthPixels) / backingScale / 2`, likewise `halfHeight` (research R3,
  R4). `safeAreaInsets` is ignored (FR-003).

**Mappings** (non-mutating, allocation-free):

| Mapping | Formula | Spec |
|---------|---------|------|
| world → view | (halfWidth + x, halfHeight − y) | FR-004 |
| view → world | (vx − halfWidth, halfHeight − vy) | FR-004, FR-005 |
| world → clip | (x ÷ halfWidth, y ÷ halfHeight) | FR-004 |

**Lifecycle**: none. A surface change means building a new camera from the new surface (FR-007).

## GameSpace

A caseless namespace for the game space's fixed facts (FR-009, FR-010).

| Member | Value | Meaning |
|--------|-------|---------|
| `shipLength` | `40` (world units) | The ship's length; its sprite is 40 × 40 pt |

Documented alongside: 1 world unit = 1 point; the world is unbounded; the ship sprite's top edge is the
ship's front, so it is drawn rotated by `heading − π/2` (−90° at heading zero).

## Unchanged

- `RenderSurface`, `SurfaceInsets` (rendering layer): read, not changed.
- `Vector2`, `Ship`, `ShipLimits` (logic layer): unchanged, apart from `ShipLimits.default`'s doc
  comment (research R9).
