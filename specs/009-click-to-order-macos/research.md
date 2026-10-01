# Research: Click to Order the Ship on macOS

**Feature**: `009-click-to-order-macos` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

The decision record for the plan. Each entry: decision, rationale, alternatives considered.

---

## R1 — Recognising the click: `NSClickGestureRecognizer` on `MetalSurfaceView`

**Decision**: In `MetalSurfaceView`'s `#if os(macOS)` code, add one `NSClickGestureRecognizer` with
`buttonMask = 0x1` (primary button only) and `numberOfClicksRequired = 1`. Its action ignores the click
when Control is held (`NSEvent.modifierFlags.contains(.control)`), and otherwise posts
`.moveOrderRequested(MoveOrderRequest(viewPoint:))` through the existing `onSurfaceChange` sink.

**Rationale**:
- The system recogniser is the platform's definition of a click: it fails on a drag beyond the click
  limits, and it fires for a trackpad tap with tap to click on, because that arrives as a primary
  click (FR-001, US1-4).
- `buttonMask = 0x1` excludes right, middle and other buttons (FR-001, clarification).
- AppKit delivers a Control-click as a primary-button event; it is a secondary click only by
  convention. Hence the explicit Control check (clarification). Command, Option and Shift pass through.
- Each click is its own recognition, so a double-click gives two orders to the same point (FR-002,
  US2-2). No `numberOfClicksRequired = 2` recogniser exists that it would have to wait for.
- It does not touch `setFrameSize`, backing-property changes or occlusion, so the surface's reporting
  is unchanged (FR-005). Title bar, resize edges and the full-screen menu bar are outside the view.

**Alternatives considered**:
- *Overriding `mouseDown`/`mouseUp`*: reimplements the drag threshold and the trackpad cases by hand.
- *A SwiftUI `SpatialTapGesture`*: rejected for 008 (R4) for the same reasons: wrong coordinate space,
  its own route to the loop.

## R2 — Inactive windows: `acceptsFirstMouse(for:)` returns `false`

**Decision**: Override `acceptsFirstMouse(for:)` to return `false`, explicitly, with a comment naming the
clarification.

**Rationale**: With `false`, AppKit uses the first click on an inactive window to activate it and does
not deliver it to the view, so the recogniser never sees it (FR-003). `false` is already `NSView`'s
default; writing it out makes the decision visible and protects it from a later "fix".

**Alternatives considered**: *relying on the default silently* (a decision with no trace in the code).

## R3 — The flip: on the main thread, against the view's own height

**Decision**: The action reads `recognizer.location(in: self)` — points, origin bottom-left, +y up,
because `MetalSurfaceView` is not flipped — and turns it into view space with a new pure helper:
`ClickPosition.viewPoint(fromBottomLeft: Vector2, heightPoints: Double) -> Vector2`, which returns
`(x, heightPoints − y)`. The height is `bounds.height` at the moment of the click.

**Rationale**:
- `MoveOrderRequest` carries a top-left view position by contract (008), and FR-007 forbids changing
  it, so the flip happens before posting.
- `bounds.height` is the geometry the surface was last reported from: `setFrameSize` reports the new
  surface synchronously, on the main thread, before any later click is handled. So the flip and the
  loop's conversion agree on the height. On the Mac the content size is a whole number of points at 1×
  and 2×, so `bounds.height` equals the camera's `heightPoints` exactly (`pixels ÷ scale`).
- A pure helper keeps the one piece of new maths testable without a view (FR-008). It imports no
  AppKit, so it builds on both platforms, like the request it feeds.

**Alternatives considered**:
- *Overriding `isFlipped` to return `true`*: `location(in:)` would then already be top-left, but
  flipping a layer-hosting view changes the coordinate space of everything 001 built in it (the layer's
  geometry and every frame calculation) for the sake of one input. Rejected.
- *Posting the bottom-left position and flipping in the loop*: needs a new field or case on the order
  request, which FR-007 rules out, and gains nothing given the height argument above.

## R4 — Tests

**Decision**: A new suite, `Tests/SwiftSkyPlatformTests/ClickPositionTests.swift`, covering contract
C1–C5: the flip of the four corners and the centre; the round trip into 008's `MoveOrderRequest.apply`
on wide, tall, 1,001 × 667 and full-screen-sized (1,512 × 982) surfaces at 1× and 2×, giving the
expected world points within 1e-9; identical results across scales; a fractional click position; and
no mirroring (a click near the top gives positive world y).

**Rationale**: Exactly the logic this feature adds. Recognition, inactive windows, modifiers and
VoiceOver are platform behaviour, checked in the quickstart. `SwiftSkyPlatformTests` already depends on
the rendering and logic layers (008 R8).

## R5 — What does not change

Everything after the post: the queue, the conversion, dropped requests, replacement, the autopilot,
arrival logging (008). `--debug-ship-spin` behaves as on iOS (008 R7). The surface's accessibility is
unchanged: macOS has no direct-interaction trait for it, and VoiceOver ordering is out of scope
(FR-009).

## R6 — Performance

**Decision**: No measurement changes. Nothing per frame is added: the recogniser runs on the main thread
only when the mouse is used, and the loop does 008's work per click. The before/after for Principle III
is quickstart check 9, on the same Mac.
