# Contract: Tap to Order

**Feature**: `008-tap-to-order-ios` | **Spec**: [../spec.md](../spec.md)

The platform layer's new API and the guarantees the tests check. Tests reach internal members with
`@testable import SwiftSkyPlatform`.

## MoveOrderRequest

```swift
public struct MoveOrderRequest: Sendable, Equatable {
    public let viewPoint: Vector2
    public init(viewPoint: Vector2)
    func apply(to state: inout SimulationState, on surface: RenderSurface) -> MoveOrderOutcome
}

enum MoveOrderOutcome: Equatable {
    case ordered(destination: Vector2)
    case noCamera
    case invalidDestination
}
```

`apply`: `guard let camera = Camera(surface: surface) else { .noCamera }`;
`let world = camera.world(fromView: viewPoint)`; `state.setOrder(to: world)` ? `.ordered(world)` :
`.invalidDestination`.

| # | Guarantee | Spec |
|---|-----------|------|
| C1 | On a w × h point surface, `viewPoint` (w/2, h/2) gives `.ordered(destination: (0, 0))` | US1-2 |
| C2 | For any surface with a camera, the destination is `(vx − w/2, h/2 − vy)`, equal to `Camera(surface:)!.world(fromView:)` | FR-006, US1-3 |
| C3 | The four corners (0, 0), (w, 0), (0, h), (w, h) give (−w/2, h/2), (w/2, h/2), (−w/2, −h/2), (w/2, −h/2) within 1e-9, on portrait phone (393 × 852), landscape phone (852 × 393), narrow Split View (320 × 1,194) and 1,001 × 667 point surfaces | SC-002, US3-1 |
| C4 | The same `viewPoint` on the same size in points at backing scales 1, 2 and 3 gives the identical destination | SC-002, US3-2 |
| C5 | After `.ordered(d)`, `state.autopilot.order?.destination == d` | FR-007 |
| C6 | A zero-width, zero-height or unusable-scale surface gives `.noCamera`, and `state` is bit-identical to before (including an existing order) | FR-006, SC-004 |
| C7 | A non-finite `viewPoint` component gives `.invalidDestination`, and `state` is bit-identical to before | FR-007 |
| C8 | Applying A then B leaves only B's order; the phase is B's evaluation, as for `setOrder` | US2-1, US2-2, SC-003 |
| C9 | A request at the ship's own view position orders it there; the next advance keeps station | US2-3 |
| C10 | After `.ordered`, `Simulation.advance(state, ticks: 1)` gives the same result as advancing a state on which `setOrder(to: d)` was called directly: the request adds nothing beyond the order | FR-008, FR-012, SC-005 |

## SurfaceEvent

```swift
public enum SurfaceEvent: Sendable, Equatable {
    // …existing cases…
    case moveOrderRequested(MoveOrderRequest)
}
```

| # | Guarantee | Spec |
|---|-----------|------|
| C11 | `post(.moveOrderRequested(_))` appends under the mutex and returns; it never waits for a frame | FR-004 |
| C12 | `applyPendingEvents()` applies events in queue order, so the request uses the surface as it stands after every earlier event in the same drain | FR-005, FR-006 |
| C13 | The request is applied in step 1 of the frame, before the step-4 advance, so that frame's advance flies it | FR-005, SC-005 |

C11 to C13 are structural (one FIFO, existing frame order) and checked by review and the quickstart.

## MetalSurfaceView (iOS)

| # | Guarantee | Spec |
|---|-----------|------|
| C14 | One `UITapGestureRecognizer`, one tap, one finger; its action posts `.moveOrderRequested(MoveOrderRequest(viewPoint: location(in: self)))` | FR-001, FR-002 |
| C15 | `accessibilityTraits == [.image, .allowsDirectInteraction]`; label unchanged | FR-014 |
| C16 | No macOS code changes, other than the platform-neutral types above building there | FR-010, SC-008 |

## Instrumentation (Debug and Profiling)

| # | Guarantee | Spec |
|---|-----------|------|
| C17 | Each applied request logs exactly one `order …` line with view and world values, or a dropped line with the reason | FR-015 |
| C18 | Each arrival logs exactly one `arrived …` line with the ship's position, including an order to the ship's own position (already arrived when applied) | FR-015, SC-007b |
| C19 | Neither method formats a string on frames without a tap or an arrival, and both are empty in Release | FR-011, FR-015 |
