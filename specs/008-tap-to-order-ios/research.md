# Research: Tap to Order the Ship on iOS

**Feature**: `008-tap-to-order-ios` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

The decision record for the plan. Each entry: decision, rationale, alternatives considered.

---

## R1 — One channel: the tap is a new `SurfaceEvent` case

**Decision**: Add `case moveOrderRequested(MoveOrderRequest)` to the existing `SurfaceEvent` enum, and
post it through `FrameLoop.post(_:)` into the same mutex-guarded queue that carries resizes, scale
changes and visibility. `applyPendingEvents()` handles it in queue order, at the frame boundary.

**Rationale**:
- FR-005 needs taps and surface events applied *in the order they happened*. One FIFO gives that for
  free; two queues would need a sequence number to merge them.
- FR-004 and 001 FR-029/FR-030 are already met by this channel: `post` only appends under a mutex and
  returns, and every payload is a value type that the compiler checks as `Sendable`.
- No new concurrency anywhere: the frame loop stays the only file with any (001 Complexity Tracking).

**Alternatives considered**:
- *A separate input queue or an atomic "latest tap" slot*: loses ordering against a resize in the same
  frame (US3-3), and a latest-only slot also merges two taps silently, which happens to give the right
  answer only because the last order wins. Rejected for the ordering problem.
- *Renaming `SurfaceEvent` to something broader (`LoopEvent`)*: more churn across 001's docs and code
  for no behaviour. The enum's doc comment is widened instead ("something the frame loop must react
  to, originating on the main thread", which it already says).

## R2 — Convert in the loop, against the applied surface

**Decision**: The event carries the tap's **view position in points**. The loop converts it with
`Camera(surface:)` built from the loop's own `surface` as it stands at that point in the queue, then
calls `SimulationState.setOrder(to:)`.

**Rationale**:
- The loop's `surface` is the geometry being drawn. Converting on the main thread with the view's
  bounds would use geometry the loop may not have applied yet (a resize posted just before the tap),
  or applied and replaced (a resize posted just after). Converting in queue order removes the race by
  construction (spec Assumptions, FR-006).
- The camera is two `Double`s and building it is a few divisions (005 FR-007), so building one per tap
  costs nothing worth caching. Nothing is built on frames without a tap.

**Alternatives considered**: *convert on the main thread and post a world point*: simpler event, but
the race above, and it would make the platform view hold a camera of its own. Rejected.

## R3 — `MoveOrderRequest`: the pure, shared, tested unit

**Decision**: A new platform-layer value type in `Sources/SwiftSkyPlatform/MoveOrderRequest.swift`:

```swift
public struct MoveOrderRequest: Sendable, Equatable {
    public let viewPoint: Vector2
    public init(viewPoint: Vector2)
    func apply(to state: inout SimulationState, on surface: RenderSurface) -> MoveOrderOutcome
}
enum MoveOrderOutcome: Equatable { case ordered(destination: Vector2), noCamera, invalidDestination }
```

`apply` is the whole of "tap → order": camera from surface (or `.noCamera`), view → world, then
`state.setOrder(to:)` (or `.invalidDestination`, state unchanged).

**Rationale**:
- It lives in the platform layer because that is the only layer allowed to name both the rendering
  layer's `Camera`/`RenderSurface` and the logic layer's `SimulationState` (001 FR-010). The logic layer
  sees only `setOrder(to:)` with a world point (FR-009) and does not change at all.
- It is a plain struct and a pure function, so `SwiftSkyPlatformTests` can test it headlessly, like
  `FrameTimeWindow` (003): no view, no layer, no `FrameLoop`, no Metal device (FR-013).
- Nothing in it is iOS-specific, so SKY-11's click posts the same value (FR-010, US4).
- The outcome is returned rather than logged inside `apply`, so the tests can check drops and the
  frame loop alone decides what to log (R6).

**Alternatives considered**:
- *Put the conversion in the logic layer*: the logic layer would have to know view points and surface
  sizes, which 001 FR-010/FR-011 forbid.
- *Inline it in `FrameLoop.applyPendingEvents()`*: untestable, because `FrameLoop` needs a
  `CAMetalLayer`. Rejected.
- *A protocol for "input source" so iOS and macOS plug in*: speculative (Principle V). A value both
  platforms post is enough.

## R4 — Recognising the tap: `UITapGestureRecognizer` on `MetalSurfaceView`

**Decision**: On iOS only (`#if os(iOS)`), `MetalSurfaceView` adds one `UITapGestureRecognizer` with
`numberOfTapsRequired = 1` and `numberOfTouchesRequired = 1`. Its action reads
`recognizer.location(in: self)` (points, top-left origin, +y down) and posts
`.moveOrderRequested(MoveOrderRequest(viewPoint:))` through the existing `onSurfaceChange` sink, which
already routes to `FrameLoop.post`.

**Rationale**:
- The system recogniser is the platform's definition of a tap: movement and duration limits, failure
  on a second finger, and deference to system edge gestures (FR-001, FR-003, spec Assumptions).
- It fires on the main thread when the finger lifts, which is where `post` expects to be called.
- `location(in:)` is in the view's own points, which is what `Camera.world(fromView:)` takes
  (005 FR-004). The view fills the window edge to edge (001 FR-003), so the whole surface, including
  outside the safe area, is tappable (FR-002).
- The view's bounds in points and the camera's size in points agree: `RenderSurface` holds
  `round(bounds × scale)` pixels, and on iOS `bounds × scale` is a whole number of pixels, so
  `pixels ÷ scale` gives back the bounds exactly.
- A gesture recogniser does not touch `layoutSubviews`, the scale-trait registration or
  `didMoveToWindow`, so size, scale and visibility reporting are unchanged (FR-003).

**Alternatives considered**:
- *Overriding `touchesEnded`*: reimplements the tap's movement, duration and multi-touch rules by hand.
- *A SwiftUI `.onTapGesture` / `SpatialTapGesture` on the representable*: puts input in the SwiftUI
  shell, whose coordinate space is the representable's frame rather than the Metal view's, and needs
  its own route to the loop. The UIKit view already owns the sink. Rejected.
- *Firing on touch-down*: faster by a few tens of milliseconds, but not a "tap" by the platform's
  definition, and it would fire at the start of every system edge swipe. Rejected (FR-001, FR-003).
- *The `onSurfaceChange` name*: it now also carries a tap. Renaming it touches 001's representable for
  no behaviour change; its doc comment is widened instead (Principle V).

## R5 — VoiceOver: `.allowsDirectInteraction`

**Decision**: On iOS the surface's `accessibilityTraits` become `[.image, .allowsDirectInteraction]`.
The label is unchanged (FR-014, clarification).

**Rationale**: With direct interaction, VoiceOver passes touches on the element straight to the app, so
the tap recogniser fires as usual. This is the documented trait for gameplay areas and costs one line.

**Alternatives considered**: *a custom accessibility action* (would need a destination to describe,
which the overlay does not yet provide); *leaving it out* (rejected by clarification). macOS needs
nothing here: VoiceOver's click on macOS is SKY-11's concern.

## R6 — Debug logging: one line per order, one per arrival

**Decision**: Under `SWIFTSKY_INSTRUMENTATION`, `Instrumentation` gains two methods:
- `recordOrder(_ outcome: MoveOrderOutcome, viewPoint: Vector2)`, which logs `order view=(x, y)
  world=(x, y)`, or `order dropped reason=no-camera|invalid-destination`.
- `recordArrival(position: Vector2, tickCount: UInt64)`, which logs `arrived world=(x, y) ticks=n`.

Both use the existing `Logger(subsystem: "com.swiftsky.app", category: "frame")` at `notice`, with
`privacy: .public` (as `summary()`). The frame loop calls `recordOrder` from `applyPendingEvents()`,
and `recordArrival` after the simulation advance when the phase is `.arrived` and this arrival has
not been logged yet. A Debug-only `arrivalLogged` flag on the loop is cleared by every applied order
and whenever the phase is not `.arrived`, and set when the line is logged. A before/after comparison
around the advance would miss one case: `setOrder` evaluates the phase at once (006), so an order to
the ship's own position is already `.arrived` before the advance. Release builds get empty inlinable no-ops, like the
existing members.

**Rationale**:
- FR-015 and SC-007b: the quickstart reads arrival within 1 point from the log, as 001 reads frame times.
- Logging happens only on frames with a tap or an arrival, never per frame. `Logger`'s interpolation
  is deferred and does not build a `String`, so the per-frame path stays allocation-free (FR-011).
- The arrival check is one enum comparison and one flag test per frame, Debug and Profiling only.
- A station-keeping correction can take the phase out of `.arrived` and back (006 clarifications), so
  "each arrival" means each transition into `.arrived`. That is the useful reading for the quickstart.

**Alternatives considered**: *the on-screen overlay* (rejected by clarification); *logging inside
`MoveOrderRequest.apply`* (would make a pure, tested function do I/O).

## R7 — `--debug-ship-spin` and taps

**Decision**: No special case. A tap sets the order through `apply` as usual, and the spin keeps using
the explicit-input `Simulation.advance(_:ticks:input:)`, which leaves the order alone (006 FR-011,
007 FR-013).

**Rationale**: The spec's edge case says this is the switch working as specified. Arrival logging still
works, because the phase is only re-evaluated by the autopilot-driven advance.

## R8 — Tests

**Decision**: One new suite, `Tests/SwiftSkyPlatformTests/MoveOrderRequestTests.swift`, covering
contract C1–C10: centre and corners on four surface shapes at 1×, 2× and 3× (SC-002); identical world
points across scales; zero-area and unusable-scale surfaces give `.noCamera` with the state unchanged
(SC-004); a non-finite view point gives `.invalidDestination` with the state unchanged; A then B leaves
B (SC-003); a request on the ship's own position orders it there; an applied request is flown by the
next `Simulation.advance` (SC-005). States are compared bit for bit, with exact `Double`
equality where the arithmetic is exact (the 005 mapping is an add and a subtract).

**Rationale**: The tests must name `SimulationState`, `Vector2` and `RenderSurface`, which
`SwiftSkyPlatform` does not re-export. Under `--explicit-target-dependency-import-check=error` a test
that imports `SwiftSkySimulation` and `SwiftSkyRendering` must declare them, so
**`SwiftSkyPlatformTests` gains the dependencies `SwiftSkyRendering` and `SwiftSkySimulation`**, as the
rendering tests gained the logic layer in 005 (005 research R8). Both are GPU-free to link, no test
creates a device, and `verify.sh`'s headless guard still applies.

**Alternatives considered**: *testing `FrameLoop`*: needs a `CAMetalLayer` and a display link, which is
not headless. The ordering guarantee (FR-005) rests on the single FIFO and is checked by review and by
quickstart check 11 (resize mid-flight, then tap).

## R9 — Performance

**Decision**: No measurement change. Per frame with no tap: unchanged, except one phase comparison.
On a frame with a tap: one `Camera` initialiser (four divisions), one subtraction pair, one
`setOrder`, which evaluates the autopilot once (006), and one log call in Debug. The queue's existing
allocation behaviour is unchanged (allocation only on frames that drain events). The before/after
measurement for Principle III is quickstart check 12: `main` and this branch on the same iOS
destination.
