# Research: Ship and Order Lines on the Debug Overlay

Decision record for [plan.md](./plan.md).

## R1 — The snapshot and its moment

- **Decision**: a rendering-layer struct, `DebugOverlayShip`, with the ship's position, velocity,
  heading and angular velocity, and an optional order (phase, destination, distance remaining). It is
  built by `DebugOverlayShip(_ state: SimulationState)` in the frame loop's step 3a, in the same branch
  that receives a due `DebugOverlayStatistics`, before step 4 advances the state.
- **Rationale**: at step 3a `state` is the result of the previous frame's ticks — the latest completed
  tick — and it is the refresh moment of the frame statistics (FR-005). The rendering layer already
  depends on the logic layer (it names `SimulationState` in `render(state:…)`), so the struct can be
  built from the state there, with the conversion tested headlessly. Scalars only: copying the 4.2 KB
  state four times a second would be harmless, but holding it in the overlay is needless (FR-011).
- **Alternatives considered**: reading `state` in `render` every frame — rejected, the values would
  change every frame, not at the refresh, and could disagree with the frame statistics' moment; adding
  ship fields to `DebugOverlayStatistics` — rejected, the instrumentation that fills it does not hold the
  state, and the statistics' fields mirror the log line (003 FR-013); showing the drawn pose — rejected
  by 013 and the spec.

## R2 — The hand-over

- **Decision**: `Renderer.updateDebugOverlay(_ statistics: DebugOverlayStatistics, ship: DebugOverlayShip)`
  replaces the one-argument form, and `DebugOverlay` gains `public var ship: DebugOverlayShip?`.
- **Rationale**: both values belong to one refresh; one call keeps them together. The overlay's `ship`
  stays optional so a test (or a renderer without a snapshot yet) writes only the six lines.

## R3 — Signed numbers

- **Decision**: `TextBuffer.writeSignedHundredths(_ value: Double, width: Int = 0, limit: Int = .max)`.
  The magnitude is rounded half away from zero to hundredths, as `writeHundredths` does; a `-` is
  written before the digits only when the value is negative and the rounded hundredths are not zero; the
  padding counts the sign. NaN writes `0.00`; magnitudes too large are clamped as the unsigned writer
  clamps them. The unsigned writer's body becomes a private helper both call.
- **Rationale**: FR-006. `writeHundredths` writes negative numbers as `0.00` by design (003), and its
  frame-time callers must not change. The writer has no overlay text, so it is compiled in every build
  next to `writeHundredths` (003 check 16 accepts that), and costs nothing in Release if unused.
- **Alternatives considered**: a `signed:` flag on `writeHundredths` — rejected, it changes a tested
  public signature for no gain.

## R4 — Degrees and the heading seam

- **Decision**: degrees = radians × 180 / π, computed in the overlay. For the heading,
  `DebugOverlay.headingDegrees(_ radians: Double) -> Double` returns 180 when the degrees round to
  −180.00 (that is, when `(degrees * 100).rounded(.toNearestOrAwayFromZero) <= -18_000`), and the
  degrees otherwise. The turn rate is converted plainly.
- **Rationale**: the ship's heading is in (−π, π] (004 FR-005), so its degrees are in (−180, 180], but a
  heading just above −π rounds to `-180.00`. The clarification says that reads `180.00`.

## R5 — Layout

- **Decision**: eight-column labels, each value right-aligned in nine columns (`-99999.99`), units after
  a space:

  ```
  pos     x     0.00 y     0.00
  vel     x     0.00 y     0.00
  speed        0.00 u/s
  heading      0.00 deg
  turn         0.00 deg/s
  order   none
  ```

  With an order, `order   ` is followed by the phase, and two lines follow:
  `dest    x   300.00 y  -200.00` and `dist        42.10 u`. The longest line is 29 characters
  (FR-007). The whole overlay, at the normal-range maxima with an order, is under 320 characters.
- **Rationale**: FR-001–FR-004; nine columns hold every normal-range value with a sign; the vectors'
  `x`/`y` keep the line under 33 characters without a second label column.

## R6 — Release and the strings check

- **Decision**: `DebugOverlayShip`, the labels, units and phase texts are inside the existing
  `#if SWIFTSKY_INSTRUMENTATION` block of `DebugOverlay.swift`; the frame-loop change is inside the
  existing `#if` of step 3a. The Release check is 003's check 16, extended with `DebugOverlayShip`
  symbols and the strings `pos     x`, `heading `, ` deg/s`, ` u/s`, `order   ` and `dest    x`.
- **Rationale**: FR-009. The phase names (`aligning`, `burning`, …) are not checked, because they are
  the Swift case names of `AutopilotPhase`, which the compiler keeps in reflection metadata in every
  build; the overlay's own copies are `StaticString`s inside the `#if`.
