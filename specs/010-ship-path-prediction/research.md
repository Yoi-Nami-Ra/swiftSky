# Research: Predict the Ship's Planned Path

**Feature**: `010-ship-path-prediction` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

The decision record behind [plan.md](./plan.md). The spec left no `NEEDS CLARIFICATION`; these are the
design choices it deferred to planning.

## R1 — Where the path lives

**Decision**: `SimulationState` gains `public private(set) var plannedPath: PlannedPath`, empty at
launch. Only `SimulationState.setOrder(to:)` writes it: after `autopilot.setOrder(_:for:)` accepts
the order, the path is predicted from the resulting ship, autopilot and tick count. A refused order
returns before either is touched.

**Rationale**: FR-001 puts the path in the state, which is the one typed hand-off to the renderer
(001 FR-012), so SKY-30 reads it from the state it is already given. `private(set)` makes FR-008
structural: `Simulation.advance` copies the state and changes only the ship, the autopilot and the
tick count, so no advance can touch the path. Every way of giving an order — tests, 008's tap, 009's
click — goes through `setOrder(to:)` (`MoveOrderRequest.apply` calls it), so FR-007 needs no change in
the platform layer.

**Alternatives rejected**: inside `Autopilot` — the autopilot is the pilot's memory between ticks
(006 R6), and the path is never read by the control law; it would also copy 4 KB every time the
autopilot is copied inside the law's callers. Held by the frame loop beside the state — breaks FR-001
and gives SKY-30 a second hand-off to read.

## R2 — Fixed-capacity storage without allocation

**Decision**: the points live in an `InlineArray<256, Vector2>` inside `PlannedPath`, behind a
`typealias Points`. The capacity is `Points.count`, so 256 is written once (FR-005). `PlannedPath`
is 4,129 bytes (measured with `MemoryLayout`, Swift 6.4).

**Rationale**: an inline array is a plain value: building it allocates nothing (FR-011), copying the
state copies the bytes, and nothing is shared between the frame loop's state and the renderer's copy.
The platform layer already uses one for the same reason (`FrameTimeWindow.swift`).

**Alternatives rejected**: `Array` / `ContiguousArray` with `reserveCapacity` — copying the state
shares the buffer, so the next write after a copy (the next order, while the renderer still holds the
previous state) triggers a copy-on-write allocation on that frame. A 256-element tuple — the same
bytes, unreadable. An unsafe buffer allocated once — not a value: no `Sendable`, no copy semantics.

## R3 — One tick function for the real flight and the prediction

**Decision**: the body of `Simulation.advance(_:ticks:)`'s loop — ask the autopilot for the tick's
input, then step the ship — moves into an internal `Simulation.tick(_ ship: inout Ship, _ autopilot:
inout Autopilot)`. `advance(_:ticks:)` calls it once per tick; the prediction calls it on local copies
of the ship and autopilot.

**Rationale**: FR-002 and SC-001 need the copy to fly the real flight bit for bit. Sharing the one
function makes that true by construction rather than by keeping two copies of the same two lines in
step. The prediction never copies the whole state per tick.

**Alternatives rejected**: calling `Simulation.advance(copy, ticks: 1)` 3,600 times — correct, but
each call copies the whole state, path included (3,600 × 4 KB ≈ 15 MB of copying for a capped
prediction). Duplicating the loop body — free today, and a silent divergence the day either copy
changes.

## R4 — When the prediction stops, and which position ends the path

**Decision**: the prediction starts from the state just after the order is given (006's `setOrder`
has already evaluated the phase). If that phase is already `arrived`, the path is the single current
position. Otherwise it repeats: one `tick`, record the ship's position, stop if the autopilot's phase
is now `arrived`, or once 3,600 ticks have run. The path ends on the ship's position after the
stopping tick, at that tick's count.

**Rationale**: the autopilot classifies the phase from the ship at the *start* of a tick, then the ship
steps (006 R6). So the state that first reports `arrived` holds the ship one step after the classified
position. The prediction stops on that same state: its end point and tick are what a test sees when it
advances the real state until `autopilot.phase == .arrived` (SC-001, SC-002), and exactly what the
frame loop logs on the arrival line, which tests the same predicate after each advance (008 FR-015,
SC-009).

**Alternatives rejected**: ending on the position the autopilot classified as arrived — one tick
earlier than anything the real state ever reports, so neither the tests nor the log could compare it
directly.

## R5 — Thinning a long flight in one pass

**Decision**: points are recorded every `spacing` ticks, starting at 1. When a point is due and the
buffer is full, the buffer is compacted: the points at even indices are kept (ticks 0, 2s, 4s, …),
the count halves to 128 and `spacing` doubles. The flight's final position is always appended as the
last point: if it fell on a sample tick it already is, otherwise it is appended, compacting first if
the buffer is full.

**Rationale**: one pass, no second flight, fixed work per tick. After the first compaction the buffer
never holds fewer than 128 points, so FR-005's "at least 128" holds, and all but the last point sit on
the order's tick plus a whole number of spacings, which is what FR-004 records. A flight of at most
255 ticks never compacts and is recorded tick by tick. At the cap, the spacing is 16 and the path
holds 226 points.

**Alternatives rejected**: two passes (fly once to count the ticks, then fly again with the exact
stride) — the smallest stride and up to 256 points, but twice the work: about 1.4 ms for a capped
flight, over SC-007. Sampling by distance — the points would not fall on ticks, losing FR-004's tick
assignment and SC-002's exact check. A ring buffer of the latest 256 — loses the start of the flight.

## R6 — The cap and the cost

**Decision**: `PlannedPath.maxFlightTicks = 60 * FixedTimestep.tickRate` (3,600), so the cap stays at
60 simulated seconds if the tick rate ever changes.

**Rationale**: 006 measured 148–189 ns per autopilot-driven tick in an optimised build (006 quickstart
check 14). A capped prediction is therefore about 0.55–0.7 ms, inside SC-007's 1 ms; a typical
on-screen order (1,000 units from rest arrives in 324 ticks) costs about 60 µs. A Debug build
(`-Onone`) is several times slower, which is why SC-007's dropped-frame check runs in a Profiling
build (optimised, with the overlay's dropped-frame counter).

**Alternatives rejected**: a cap in ticks (a literal 3,600) — the same number today, wrong if the tick
rate changes. No cap — a ship with a zero limit would never stop being predicted (FR-006, 006 FR-013).

## R7 — Equality and test bits

**Decision**: `PlannedPath` writes its own `==`: count, the three tick numbers, the arrival flag, then
points `0..<count` (the unused slots are ignored). `StateBits.swift` gains `bits(_ path:)`, and
`bits(_ state:)` appends it.

**Rationale**: `InlineArray` does not conform to `Equatable` (checked with Swift 6.4), and
`SimulationState` is `Equatable`. Appending the path to the state's bits makes 006's ten-run
determinism test (`tenRunsAreIdentical`) cover the path as well (SC-006) with no new scenario.

**Alternatives rejected**: comparing all 256 slots — unused slots would make two equal paths unequal
after different compaction histories.

## R8 — The Debug order log line

**Decision**: `Instrumentation.recordOrder(_:viewPoint:)` gains a `path: PlannedPath` parameter. For
an applied order, the existing line gains
`predicted=(x, y) ticks=N points=P arrives=yes|no`. The point and tick use the same interpolation as
the arrival line (`arrived world=(x, y) ticks=N`), and the flag uses `Logger`'s `.answer` format. The
Release no-op gains the same parameter.

**Rationale**: FR-014 and SC-009 compare the two lines by eye or with `grep`, so the formats must
match. `Logger` defers the formatting and builds no `String` on the loop thread (008 R6), and the line
is written only on a frame that applies an order.

**Alternatives rejected**: a separate prediction line — a second line per order to pair up, for the
same information.

## R9 — Tests

**Decision**: a new `PlannedPathTests.swift` suite:
- the thinning rule tested directly, by feeding a path one synthetic position per tick for every
  flight length from 0 to 3,700 ticks, each position encoding its own tick (SC-003, FR-004, FR-005);
- predictions over 006's rest grid (80 orders) and moving-start grid (96 orders), each checked against
  the real flight, advanced one tick at a time: every point bit for bit at its assigned tick, the end
  point and tick on the first `arrived` state (SC-001, SC-002);
- capped flights: zero thrust, and zero angular acceleration facing away (SC-004), plus the work bound
  on every prediction in the suite;
- per-order behaviour: advancing with and without explicit input, re-ordering, refusal, no order,
  already there, and FR-009's unchanged ship and autopilot (SC-005, edge cases);
- determinism through the extended `StateBits` (SC-006, R7).

The grids reuse `AutopilotTests`' static data and the module-level `fly` helper.

## R10 — Before/after measurement

**Decision**: the 006 check 14 method — a throwaway `-O` executable built from
`Sources/SwiftSkySimulation/*.swift`, timed with `ContinuousClock`, allocations counted with
`malloc_zone_statistics` — measures (a) a capped prediction and a 1,000-unit prediction, and (b) a
single-tick `advance` call on `main` and on this branch, since the state grows from 114 to 4,249 bytes and is copied once per call.

**Rationale**: Principle III wants a before/after number for anything on the hot path, and SC-007 a
timing for the prediction that the automated tests deliberately do not take (spec clarification Q3).
