# Research: Ship State and Newtonian Motion

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-09-30

Decision record for `/speckit-plan`. The Technical Context had no open unknowns: the language,
toolchain, fixed timestep and pure `advance` function already exist from 001. What needed deciding is
the shape of the new values, how input reaches `advance` without changing the frame loop, how angles
are held, where the trigonometry comes from in a layer that imports nothing, and how "byte-identical"
and "no allocation" are checked. Each entry gives the decision, why, and what was rejected.

## R1. How the control input reaches `advance` (FR-006, FR-010, FR-011)

**Decision**: `Simulation.advance(_:ticks:input:)` gains an `input: ControlInput` parameter with a
default of `.neutral`. Every tick of one call uses that input. The frame loop's existing call,
`Simulation.advance(state, ticks: ticks)`, compiles unchanged and means the neutral input (FR-010).

**Rationale**: the input is per call, as the clarification decided, so it is an argument, not part of
the state. A default keeps `FrameLoop.swift` untouched, which is what SC-005's "unchanged app" rests
on, and the existing 001 tests keep passing without edits.

**Rejected**:
- **Storing the input in `SimulationState`.** The state would then describe what someone *wanted*
  as well as what *is*, and SKY-25's autopilot, which produces input from state, would read its own
  previous output back.
- **A second function, `advance(_:ticks:)` plus `advance(_:ticks:input:)`.** Two entry points to one
  rule. A default argument gives the same call sites with one body.
- **A per-tick array of inputs.** It allocates, and the frame loop has one input per frame anyway.

## R2. Angle units inside the model (FR-003, FR-004, FR-005, FR-008)

**Decision**: heading, rate of turn and the two angular limits are held in **radians** and radians
per second (squared). The defaults are written once, in `ShipLimits.default`, as the radian values of
180 °/s and 360 °/s², with the degree values in the doc comment.

**Rationale**: the trigonometric functions take radians. Converting at every tick would add two
multiplications and a rounding step to the hot path, and would make "byte-identical" depend on where
the conversion happens. The spec states the defaults in degrees for readers; the tests convert once.

**Rejected**: degrees in storage (a conversion per tick, per angle); a `Measurement`/`Angle` wrapper
type (Foundation, and an abstraction nothing else needs yet — Principle V).

## R3. Trigonometry in a layer that imports nothing (FR-009, FR-012, FR-014)

**Decision**: `ShipMotion.swift` imports **`Darwin`** for `cos` and `sin`, guarded by
`#if canImport(Darwin)`, with `Glibc` as the other branch so the file stays portable. It is the only
file in `SwiftSkySimulation` with an import.

**Rationale**: the Swift standard library has no elementary functions. `Darwin` is the C library, not a
framework: it brings no Metal, UIKit, AppKit or SwiftUI type, and no SwiftPM target dependency, so
Principle I's "logic must not depend on Metal or SwiftUI" and FR-013 of 001 (the target declares no
dependencies) both hold. `Package.swift` changes only its "imports nothing" comment. `libm`'s `cos`/`sin` are pure functions of
their argument, so on a given platform and binary they return the same bits every run, which is all
SC-004 and 001 SC-013 ask for.

**Rejected**:
- **`import Foundation`.** Far more surface than two functions need.
- **swift-numerics' `RealModule`.** A third-party dependency for two functions (Principle V).
- **A hand-written polynomial.** Faster to write than to prove accurate, and still no more
  deterministic than `libm` on one platform.
- **Caching the heading's unit vector in the state.** It would save the two calls on ticks without
  turning, but the vector and the angle could drift apart, and the saving is irrelevant at ≤ 4 ticks
  per frame (R7).

Cross-platform bit-equality (a Mac and an iPhone giving the same bits) is **not** promised: the spec
asks for identical results across runs, and SKY-26's prediction runs in the same process as the ship.

## R4. The per-tick rule, precisely (FR-008, FR-009, clarifications)

**Decision**, with `dt = FixedTimestep.tickDuration`:

1. `target = input.turn × limits.maxAngularSpeed`
2. `maxStep = limits.maxAngularAcceleration × dt`
3. `angularVelocity` moves toward `target`: if `|target − angularVelocity| ≤ maxStep` it becomes
   `target` exactly; otherwise it changes by `maxStep` toward `target`.
4. `heading += angularVelocity × dt`, then wrapped into (−π, π] (R5).
5. If `input.thrust > 0`: `velocity += (cos heading, sin heading) × input.thrust × limits.maxThrustAcceleration × dt`.
6. `position += velocity × dt`.

**Rationale**: steps 3→4 and 5→6 update each rate before the quantity it drives, which is
semi-implicit Euler (FR-009). Rotation comes before translation (clarification 3). The snap in step 3
is what makes the rate reach its target and zero exactly, with no overshoot or sign change
(US2 scenario 2, SC-003). Skipping step 5 when thrust is zero keeps an unthrusted ship's velocity
bit-for-bit unchanged — no `v + 0 × cos θ` that could turn a `+0` into a `-0` — which is what SC-001
checks, and it saves the two trigonometric calls on every coasting tick.

Clamping |ω| ≤ `maxAngularSpeed` needs no separate step: `target` is within it (the input is clamped
to −1…1), and step 3 never moves past `target`.

**Rejected**:
- **Explicit Euler (position from the old velocity).** Loses energy accuracy and is not what the
  ticket names.
- **Clamping the rate after adding a full acceleration step.** Overshoots the target, then snaps back:
  the rate would jitter around a held turn.
- **Velocity-Verlet / RK4.** More accurate than the game needs, and SKY-26 would have to copy it.

## R5. Heading wrap (FR-005)

**Decision**: after step 4, if the heading is outside (−π, π], replace it with
`heading.remainder(dividingBy: 2π)` and map an exact `−π` to `π`. Within range it is left untouched.

**Rationale**: `remainder(dividingBy:)` is IEEE 754 exact and correctly handles any rate, even a
custom limit large enough to turn more than once a tick. Leaving in-range values untouched means the
common tick does no extra arithmetic and changes no bits.

**Rejected**: a single `± 2π` correction (wrong when a tick turns more than a full turn with a custom
limit); wrapping into [0, 2π) (the spec fixes (−180°, 180°]).

## R6. Sanitising input and limits (FR-003, FR-007)

**Decision**: `ControlInput.init(thrust:turn:)` and `ShipLimits.init(...)` sanitise on construction:
non-finite → 0, then clamp (thrust to 0…1, turn to −1…1, limits to ≥ 0). Stored properties are
`let`, so a sanitised value cannot become unsanitised.

**Rationale**: validating once at construction means the per-tick rule never checks, and every value
the rule sees is already in range. `let` properties make the invariant structural.

**Rejected**: clamping inside the per-tick rule (repeated work, and the invariant lives in two places);
a failable or throwing initialiser (a bad input is not an error the caller can do anything useful
about, and the spec says to treat it as 0).

## R7. Cost on the hot path (FR-013, Principle III)

**Decision**: the step works entirely on stored `Double`s in value types — no array, no string, no
class, no closure, no existential — so it cannot allocate. Per tick it costs at most one `cos`, one
`sin` and about twenty floating-point operations. The before/after evidence Principle III requires
comes in two parts:

1. **Always, headlessly** (quickstart check 11): a throwaway release-mode (`-O`) benchmark, built in
   the session scratchpad with `swiftc` from the logic layer's sources — once from `main`, once from
   this branch — times 10 million `Simulation.advance(_, ticks: 1, …)` calls and counts heap
   allocations across them with `malloc_zone_statistics`. It records ns per tick before and after,
   and allocations (which must be 0 after). It is not checked in: it is evidence, not a test.
2. **On device** (quickstart checks 8, 9): the SKY-3/SKY-4 Instruments allocation check and the 003
   overlay's frame time, before and after, when a device session is available.

**Rationale**: part 1 isolates exactly the code this feature adds to the hot path, runs anywhere, and
cannot be skipped for want of a device; part 2 is the frame-level check SC-005 names. A standalone
executable has no parallel test runner around it, so the malloc counter measures only the loop.

**Rejected**: a `malloc_zone_statistics` check inside the Swift Testing suite (the parallel test
runner's own allocations make it noisy); a checked-in benchmark target (Principle V — nothing needs it
after this measurement); `@inline(__always)` / `@inlinable` annotations (no measured need).

## R8. Checking "byte-identical" (FR-011, FR-012, SC-001, SC-004)

**Decision**: the tests compare bit patterns, not `==`. A test-only helper flattens a state into
`[UInt64]` — the tick count and each `Double`'s `bitPattern` — and the tests compare those arrays.
`SimulationState` stays `Equatable` with synthesised `==`.

**Rationale**: `Double`'s `==` treats `+0` and `−0` as equal and `NaN` as unequal to itself, so it
would pass two states that differ in bits and fail two that are identical. SC-001 and SC-004 say
"bit-for-bit".

**Rejected**: a custom `==` on the state (would change the meaning of equality for every caller to
serve a test); `withUnsafeBytes` over the whole struct (layout padding is not guaranteed to be
deterministic, and it would compare the limits' padding too).

## R9. What the renderer sees (spec "Extended", 001 FR-012b)

**Decision**: nothing in `SwiftSkyRendering` changes. The ship rides inside `SimulationState`, which
`Renderer.render(state:…)` already receives by value, and the renderer ignores it until SKY-27.

**Rationale**: FR-001 requires the state to stay a plain copied value; it does. Adding a field is
source-compatible with every existing use of `SimulationState`, since the existing initialisers are
kept and give the default ship.

**Rejected**: a separate ship hand-off (a second seam for a value the state already carries).

## R10. File layout (Principle I, V)

**Decision**: three new files in `Sources/SwiftSkySimulation/`: `Vector2.swift` (the plane vector and
its four operators), `Ship.swift` (`Ship`, `ShipLimits`, `ControlInput`) and `ShipMotion.swift` (the
per-tick rule, the only import). `SimulationState.swift` and `Simulation.swift` change. One new test
file, `ShipMotionTests.swift`, plus a small `StateBits.swift` test helper.

**Rationale**: one file per concept, as the layer already has (`FixedTimestep`, `TimeAccumulator`).
Putting the rule apart from the types keeps the one `import` in one small file.

**Rejected**: `simd`'s `SIMD2<Double>` for the vector — it would work, but its arithmetic can be fused
or vectorised differently from scalar code, and a four-operator `Vector2` is smaller than the reasoning
needed to rule that out.
