# Research: Interpolate Rendering Between Simulation Ticks

Decision record for 013. Each entry: decision, rationale, alternatives considered.

## R1 — The fraction is derived from `unconsumed`, and `consume` keeps `unconsumed` in range

**Decision**: `TimeAccumulator` gains a read-only `tickFraction: Double`, computed as
`unconsumed / FixedTimestep.tickDuration` and clamped into `0 ... 1.0.nextDown`. `consume(elapsed:)`
also clamps `unconsumed` to `max(0, …)` after subtracting whole ticks.

**Rationale**: `wholeTicks` is `floor(unconsumed / tickDuration)`. When `unconsumed` is a hair below a
whole number of ticks, the division can round up to that whole number, and the subtraction then
leaves `unconsumed` a few ulps below zero, which breaks the documented "always non-negative"
invariant that already exists. The same rounding can leave `unconsumed` a hair at or above one
tick. Clamping both places makes FR-001 hold whatever the floating-point error. The catch-up path
already uses `truncatingRemainder`, which stays in `[0, tickDuration)`.

**Alternatives considered**: storing the fraction as separate state (two sources of truth); integer
nanosecond time (larger change, and the frame loop hands in `Double` seconds from `CAMetalDisplayLink`).

## R2 — `ShipPose` is a logic-layer value, and the blend is a static function on it

**Decision**: a new `ShipPose` struct in `SwiftSkySimulation` (position `Vector2`, heading `Double`),
built from a `Ship`, with `static func blended(from:to:fraction:) -> ShipPose`.

**Rationale**: the blend is pure maths on the logic layer's own types (FR-004, Principle I), and it
must be testable with `StateBits`. The rendering and platform layers already import the logic layer.
A two-field value is what FR-005 asks the frame loop to hold instead of a ~4.2 KB state copy.

**Alternatives considered**: passing a whole `Ship` (carries velocity, limits and angular velocity
that nothing blends); putting the blend in the rendering layer (SKY-42's camera and SKY-30's overlay
will need the same pose, and the logic layer is where the tick poses come from).

## R3 — Blend arithmetic and its exact cases

**Decision**:
- `fraction == 0` returns `from` whole, bit for bit.
- Each position component: `a == b ? a : a + (b − a) × t`.
- Heading: if `from == to`, keep `from`. Otherwise `delta = (to − from).remainder(dividingBy: 2π)`,
  which lies in `[−π, π]`; a `delta` of `−π` becomes `+π` (counter-clockwise, clarification 4); the
  result is `Ship.wrapped(from + delta × t)`, in `(−π, π]` (clarification 3).

**Rationale**: `a + (b − a) × 0` is not always `a` bit for bit (`−0 + 0 = +0`), and neither is
`a + 0 × t`. Returning the input in the equal cases gives FR-003's bit-exact endpoints without a
special bit test. `remainder` is the shortest signed difference; `Ship.wrapped` is the one wrap the
logic layer already uses (004 research R5), and returns in-range values untouched.

**Alternatives considered**: `simd_mix` (same rounding, adds a `simd` dependency to a layer that uses
plain `Double`); blending unit vectors and taking `atan2` (costlier, and not linear in angle);
`a × (1 − t) + b × t` (exact at `t = 1`, which is never reached, but not at `t = 0` for `−0`).

## R4 — The previous pose is captured inside `Simulation.advance`, held by the frame loop

**Decision**: both `Simulation.advance` overloads gain a variant with a trailing
`previousPose: inout ShipPose` parameter. For `ticks > 0` it records `ShipPose(ship)` immediately
before the last tick of the loop; for `ticks == 0` it leaves `previousPose` alone. The existing
overloads become thin wrappers that discard it, so every caller and test is unchanged. The frame loop
keeps one `ShipPose` field, initialised from the initial state's ship.

**Rationale**: the rule of FR-005 (unchanged on 0-tick frames, the pose before the last tick on
multi-tick frames, byte-identical state) is then pure, headless and tested next to `advance` with
`StateBits`. Recording inside the existing loop costs one 24-byte copy per frame and keeps one state
copy, where splitting the frame's advance into `ticks − 1` and `1` would copy the ~4.2 KB state twice.
The value itself lives in the platform layer, as the ticket says.

**Alternatives considered**: splitting the advance in the frame loop (two state copies, and the rule
untested because `FrameLoop` needs Metal); storing the previous pose in `SimulationState` (it is a
presentation concern, and would enter `StateBits` and the planned path's determinism tests).

## R5 — The drawn pose is a `render` argument

**Decision**: `Renderer.render(state:shipPose:surface:drawable:timestamp:)`. The frame loop computes the
drawn pose — `ShipPose.blended(from: previousPose, to: ShipPose(state.ship), fraction: accumulator.tickFraction)`,
or `ShipPose(state.ship)` under `--no-interpolation` — and `encodeShip` places the sprite from it.

**Rationale**: FR-007 wants one drawn pose available to everything that draws from the ship, so
SKY-30 and SKY-42 read the same value the sprite uses. The renderer still reads the state for
everything else, and nothing is written back (FR-006). An argument is a plain value: no allocation.

**Alternatives considered**: handing the renderer the previous pose and fraction and blending there
(every future consumer would repeat the blend, and `--no-interpolation` would have to reach the
renderer); a mutable `drawnPose` property set before `render` (two-step protocol, easy to forget).

## R6 — `--no-interpolation` joins `DebugShipOptions`

**Decision**: `DebugShipOptions` gains `interpolates: Bool` (false when `--no-interpolation` is
present), passed to the frame loop as `debugNoInterpolation`, set once before `start()` like
`debugShipSpin`. Release builds neither parse nor carry it (FR-008).

**Rationale**: the ship switches already live there with their tests (`DebugShipOptionsTests`).

## R7 — Tests

**Decision**:
- `ShipPoseTests` (simulation): fraction 0 and equal pairs bit for bit; 1,000+ seeded pairs and
  fractions checked against the segment (SC-001); seam pairs both ways, the opposite-heading
  convention and the range (SC-002).
- `TimeAccumulatorTests` (extended): 10,000+ elapsed values, including 0, negative, non-finite,
  sub-tick, exact multiples and 10 s stalls; `tickFraction` in `[0, 1)` and `unconsumed ≥ 0` after
  every one (SC-003).
- `SimulationTests` (extended): 0, 1, 2 and 4 ticks, with the autopilot and with an explicit input;
  `previousPose` per FR-005 and the state byte-identical to the plain overload (SC-003).
- `DebugShipOptionsTests` (extended): the new switch.

Seeded pseudo-random values use a local fixed-seed generator so runs are deterministic (SC-006).

## R8 — Visual and allocation checks

**Decision**: the by-eye checks (SC-004) are run on the development Mac at 120 Hz with and without
`--no-interpolation`, an order flown and `--debug-ship-spin`, and recorded in the quickstart.
SC-005 repeats 011's check 25 with "the method" of `specs/011-draw-allocation-counter/quickstart.md`:
an optimised build carrying the counter, 60 s with orders on each platform.
