# Contract: Camera and GameSpace

**Feature**: `005-game-space-camera` | **Module**: `SwiftSkyRendering`

The public surface this feature adds, for SKY-10, SKY-11, SKY-27 and SKY-30. Shapes are in
[data-model.md](../data-model.md); reasons in [research.md](../research.md).

## `public struct Camera: Sendable, Equatable`

```swift
public init?(surface: RenderSurface)

public let halfWidth: Double      // points
public let halfHeight: Double     // points
public var widthPoints: Double { get }
public var heightPoints: Double { get }

/// World point → view position (points from the top-left, +y down).
public func view(fromWorld world: Vector2) -> Vector2

/// View position → world point.
public func world(fromView view: Vector2) -> Vector2

/// World point → normalised device coordinates (edges at ±1, +y up).
public func clip(fromWorld world: Vector2) -> Vector2
```

### Guarantees

| # | Given | Then |
|---|-------|------|
| C1 | a surface with zero width or zero height | `init?` returns `nil` |
| C2 | a backing scale that is `0`, negative, `.nan` or `±.infinity` | `init?` returns `nil` |
| C2a | a finite, positive scale so extreme that a half-extent overflows to ∞ or underflows to a subnormal | `init?` returns `nil` |
| C3 | any other surface | a camera with `halfWidth = widthPixels / backingScale / 2` (likewise height), both finite and > 0 |
| C4 | two surfaces differing only in `safeAreaInsets` | equal cameras |
| C5 | the same point size at backing scales 1, 2, 3 (exact pixel counts) | equal cameras |
| C6 | `view(fromWorld: .zero)` | `(halfWidth, halfHeight)` |
| C7 | `view(fromWorld: (−halfWidth, +halfHeight))` | `(0, 0)`; `(+halfWidth, −halfHeight)` → `(widthPoints, heightPoints)` |
| C8 | `clip(fromWorld: .zero)` | `(0, 0)`; `(±halfWidth, ±halfHeight)` → exactly `(±1, ±1)` |
| C9 | any view position `v` with both coordinates within ±10⁶ points | `view(fromWorld: world(fromView: v))` within 1e-9 of `v` per axis |
| C10 | any finite input, on or off the surface, below 10¹² in magnitude, at a backing scale no greater than 10⁶ (real displays are 1–3) | a finite result; no clamping (beyond that, the result is finite whenever it is representable) |
| C11 | a non-finite input | a non-finite result, passed through |

## `public enum GameSpace`

```swift
public static let shipLength: Double   // 40 world units
```

Doc comments carry the scale (1 unit = 1 pt), the unbounded extent and SKY-27's sprite note (draw the
sprite rotated by `heading − π/2`: its top edge is the ship's front).
