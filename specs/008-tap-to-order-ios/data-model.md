# Data Model: Tap to Order the Ship on iOS

**Feature**: `008-tap-to-order-ios` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

Every type is a value type. Nothing in the logic or rendering layers changes.

## MoveOrderRequest (new, platform layer, platform-neutral)

"Order the ship to the world point under this view position." Posted by the iOS tap (and later by
SKY-11's click), carried into the loop inside `SurfaceEvent`.

| Field | Type | Meaning |
|-------|------|---------|
| `viewPoint` | `Vector2` | Position on the surface in points, origin top-left, +y down (005 view space) |

- `Sendable`, `Equatable`. No validation at construction: any value, even non-finite, is legal, and
  `apply` decides what it becomes (FR-006, FR-007).
- `apply(to: inout SimulationState, on: RenderSurface) -> MoveOrderOutcome`. Pure, no allocation.

## MoveOrderOutcome (new, platform layer, internal)

| Case | When | State after |
|------|------|-------------|
| `.ordered(destination: Vector2)` | The surface has a camera and the world point is finite | Order replaced by one to `destination` (006 FR-002) |
| `.noCamera` | `Camera(surface:)` is `nil`: zero area or unusable scale (005 FR-008) | Unchanged |
| `.invalidDestination` | The world point is not finite, so `setOrder(to:)` returns `false` (006 FR-002) | Unchanged |

Used by the frame loop for Debug logging (R6) and by the tests.

## SurfaceEvent (changed, platform layer)

Gains one case; the others are unchanged.

| Case | Payload | Applied as |
|------|---------|-----------|
| `moveOrderRequested` | `MoveOrderRequest` | `request.apply(to: &state, on: surface)` with the loop's surface as it stands at that point in the queue |

Order of application is queue order (FR-005): a `.resized` posted before a tap is applied before it.

## Tap (platform glue, iOS only, not a type)

`UITapGestureRecognizer`: one tap, one finger, on `MetalSurfaceView`. Its `location(in:)` becomes
`MoveOrderRequest.viewPoint`. Exists only in `#if os(iOS)` code.

## Instrumentation additions (Debug and Profiling only)

| Method | Logs | Called |
|--------|------|--------|
| `recordOrder(_:viewPoint:)` | `order view=(x, y) world=(x, y)`, or `order dropped view=(x, y) reason=…` | Once per applied `moveOrderRequested` |
| `recordArrival(position:tickCount:)` | `arrived world=(x, y) ticks=n` | Once per arrival: phase `.arrived` after the advance, not yet logged since the last order or the last time the phase was not `.arrived` |

Release: empty inlinable no-ops.

## Unchanged and reused

- `SimulationState.setOrder(to:)`, `MoveOrder`, `Autopilot` (006).
- `Camera(surface:)`, `Camera.world(fromView:)` (005).
- `RenderSurface` (001).
