# Research: Game Space and Camera

**Feature**: `005-game-space-camera` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

The spec left no `NEEDS CLARIFICATION`. These are the design decisions the plan rests on.

## R1 — Where the camera lives: the rendering layer

- **Decision**: `Camera` and the ship length go in `SwiftSkyRendering`, in two new files beside
  `RenderSurface.swift`.
- **Rationale**: the camera is built from a `RenderSurface`, which is a rendering type, and both its
  consumers can reach the rendering layer: the renderer (SKY-27, SKY-30) is in it, and the platform
  layer's input code (SKY-10, SKY-11) already depends on it (spec FR-011). The logic layer must not
  know about surfaces or points (Principle I).
- **Alternatives considered**: the logic layer (rejected: it would need a notion of a screen, and it
  declares no dependencies); the platform layer (rejected: the renderer cannot import it — the build
  forbids rendering → platform).

## R2 — Point type: `Vector2` from the logic layer, for all three spaces

- **Decision**: every mapping takes and returns `Vector2` (two `Double`s): world points, view
  positions and normalised device coordinates alike. Doc comments name the space of each argument
  and result.
- **Rationale**: world points *are* `Vector2`s — the ship's position is one — so SKY-27 passes
  `ship.position` straight in. `SwiftSkyRendering` already depends on `SwiftSkySimulation`. Keeping one
  `Double` type end to end is what makes the 1e-9 round trip and the exact corner values reachable.
- **Alternatives considered**: `CGPoint` for view positions (rejected: pulls CoreGraphics into a pure
  mapping for no gain; the input tickets convert once); `SIMD2<Float>` for clip space (rejected: loses
  the exactness the tests check; SKY-27 converts to `Float` when it writes a vertex); separate
  `ViewPoint` / `ClipPoint` wrapper types (rejected under Principle V: three types for one struct with
  no behaviour, before any caller has confused two spaces).

## R3 — Stored form: half-extents in points, validated once

- **Decision**: `Camera` stores `halfWidth` and `halfHeight` in points, both `let`, computed in a
  failable `init?(surface:)` as `Double(widthPixels) / backingScale / 2` (and height alike). The
  initialiser returns `nil` when the surface is not renderable (001 FR-027a) or the backing scale is
  not finite and positive (spec FR-008), and also when a computed half-extent is not a normal number
  — an extreme finite scale can overflow `pixels / scale` to ∞ or underflow it to a subnormal, and
  neither is safe to divide by. It also exposes `widthPoints` / `heightPoints` computed from
  them for tests and readers.
- **Rationale**: every mapping needs w/2 and h/2 and nothing else, so storing them makes each mapping
  one add or subtract per axis. Validating once means no mapping can divide by zero: a `Camera` that
  exists always has positive, finite half-extents. The two checks together cover every `RenderSurface`
  value — `UInt32` pixels are finite and non-negative, so non-renderable means exactly "zero width or
  zero height".
- **Alternatives considered**: a non-failable init with an `isValid` flag (rejected: callers could
  map through an invalid camera); storing the whole `RenderSurface` (rejected: carries the safe-area
  insets the camera must ignore, and invites re-deriving points on every call).

## R4 — Exactness: divide, never multiply by a reciprocal

- **Decision**: world → clip computes `x / halfWidth` and `y / halfHeight`. Points are
  `pixels / backingScale`, not `pixels * (1 / backingScale)`.
- **Rationale**: IEEE 754 division is correctly rounded, so `halfWidth / halfWidth` is exactly 1 and
  the surface edges land at exactly ±1 (SC-001). `x * (1 / halfWidth)` rounds twice and can miss 1 by
  one ulp. Likewise `3003 / 3` is exactly 1001, so the same point size at 1×, 2× and 3× gives
  bit-identical half-extents and therefore identical mappings (SC-003) — for any point size whose
  pixel counts are exact, which is every size the platform produces at integer scales.
- **Alternatives considered**: precomputed reciprocals for speed (rejected: two divisions per mapped
  point is nothing next to a frame, and exactness is a tested requirement).

## R5 — Round-trip tolerance

- **Decision**: test view → world → view over 1,000 deterministic positions from a fixed grid spanning
  −1× to +2× the surface in each axis, asserting `abs(back − start) <= 1e-9`.
- **Rationale**: each direction is one add and one subtract per axis on values below ~10⁴ points, so
  the error is a few ulps (~10⁻¹²) — three orders of magnitude inside the spec's bound. The bound
  only holds for moderate magnitudes: at 10⁶ points two ulps are ~2.3 × 10⁻¹⁰, but at 10⁸ one ulp
  already exceeds 10⁻⁹, which is why FR-005 and C9 are limited to ±10⁶ points. A fixed grid
  keeps the test deterministic without a seeded generator.
- **Alternatives considered**: a random generator (rejected: needs a seed type and adds nothing a grid
  misses); exact equality (rejected: `(vx − w/2) + w/2` is not always exactly `vx`).

## R6 — No live wiring

- **Decision**: nothing in the frame loop, renderer or input code builds or holds a `Camera` in this
  feature.
- **Rationale**: no consumer exists yet (spec Assumptions, Principle V). SKY-27 will build one in the
  renderer where the surface already arrives on each draw, or hold one alongside the frame loop's
  `surface`, which is replaced only on surface events — either way, never per frame. Adding an unused
  stored camera now would be dead state.
- **Alternatives considered**: storing a camera in `FrameLoop` beside `surface` (rejected: unread
  until SKY-27, and SKY-27 may prefer the renderer).

## R7 — Ship length and sprite note: `GameSpace` namespace

- **Decision**: a caseless `public enum GameSpace` in `GameSpace.swift` holds
  `public static let shipLength: Double = 40`, with doc comments recording the scale (1 unit = 1 pt),
  the unbounded extent, and SKY-27's sprite note (top edge = front, so rotate by `heading − π/2`,
  i.e. −90° at heading zero).
- **Rationale**: one place for the ship size (spec FR-009) and the decisions around it, beside the
  camera (FR-010). A caseless enum cannot be instantiated.
- **Alternatives considered**: a static on `Camera` (rejected: the ship's size is not a property of
  the view); on `Ship` in the logic layer (rejected: the ticket places it beside the camera, and the
  logic layer does not need it — the motion rule treats the ship as a point).

## R8 — Tests: `CameraTests` in the rendering test target

- **Decision**: a new `Tests/SwiftSkyRenderingTests/CameraTests.swift` Swift Testing suite. The
  rendering test target gains `SwiftSkySimulation` as a declared dependency so the tests can name
  `Vector2`.
- **Rationale**: `verify.sh` builds with `--explicit-target-dependency-import-check=error`, so a test
  that imports a module its target does not declare fails the build. The logic layer has no GPU
  dependency, so adding it keeps the target headless; `verify.sh`'s Metal-device guard still applies.
  Exact expectations use `==` on `Double`, which is right here: the values are compared, not their
  bit patterns (no signed-zero requirement in this spec).
- **Alternatives considered**: `@_exported import SwiftSkySimulation` in the rendering layer (rejected:
  changes every rendering client's namespace to save one line in `Package.swift`).

## R9 — Retuning note for the default limits

- **Decision**: replace `Ship.swift`'s "Provisional. Retune once SKY-23 fixes what a world unit is on
  screen." with a line stating that one world unit is one point (005), so 200 units/s² is 200 pt/s².
  No value changes (spec FR-012).
- **Rationale**: the note is now stale; a reader should not go looking for a retune that was decided
  against.

## R10 — Performance evidence

- **Decision**: structural evidence only: `Camera` is a struct of two `Double`s with no reference or
  growable storage, mappings are non-mutating arithmetic, and nothing on the frame path calls it yet.
- **Rationale**: Principle III asks for before/after measurement when a feature touches the hot path.
  This one does not (R6), and the running app's code path is unchanged. SKY-27, which puts the camera
  on the draw path, carries that measurement.
