# Research: Ship Sprite Rendering

**Feature**: `007-ship-sprite-rendering` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

The decision record for the plan. Each entry: decision, rationale, alternatives considered.

---

## R1 — Where the image ships, and how the build finds it

**Decision**: A byte-identical copy of `design/sprites/ship.png` lives at
`Sources/SwiftSkyRendering/Resources/ship.png` and is declared in `Package.swift` as
`resources: [.copy("Resources/ship.png")]` on the `SwiftSkyRendering` target. The renderer finds it with
`Bundle.module.url(forResource: "ship", withExtension: "png")`, the same bundle its compiled shaders
already come from. `Scripts/verify.sh` gains a stage that runs `cmp` on the two files and fails if they
differ (FR-002, SC-008a).

**Rationale**:
- The rendering layer already owns its resources (the shader library in `Bundle.module`), and both apps
  already embed that bundle. One copy serves both platforms, and neither app target changes.
- `.copy` rather than `.process`: processing may re-encode a PNG (Xcode's PNG compression rewrites
  images for iOS), so the shipped bytes would stop matching the design file. `.copy` ships the bytes
  verbatim.
- SwiftPM resources must live inside the target's directory, so the design file cannot be referenced
  where it is. A checked copy follows the clarification (design file canonical, copy byte-identical).

**Alternatives considered**:
- *Each app's asset catalog*: two copies, recompressed by the asset compiler, and a platform-layer load
  that would have to hand the renderer an image. Rejected.
- *A symlink from the target into `design/`*: SwiftPM's handling of symlinked resources is not
  something the project relies on anywhere, and a broken link fails far from its cause. Rejected in
  favour of the explicit `cmp` check.
- *A build phase that copies the file*: more machinery than a checked copy, and still needs the check.

## R2 — Decoding: Core Graphics on the CPU, into premultiplied sRGB bytes

**Decision**: A pure CPU type, `ShipImageBitmap`, decodes the PNG with ImageIO
(`CGImageSourceCreateWithURL` → `CGImage`) and draws it once into an 80 × 80 `CGContext` with the sRGB
colour space and `premultipliedLast` alpha, 8 bits per channel, RGBA byte order. It rejects a missing
file, data that does not decode, and an image that is not 80 × 80. The bytes are uploaded to the GPU
by the renderer (R4). Like `GlyphAtlasBitmap` (002), the CPU half is separate so the headless tests can
check it.

**Rationale**:
- The file is 16 bits per channel. Drawing it into an 8-bit sRGB context converts depth and colour
  space in one well-defined step, whatever the file's own encoding.
- MetalKit's texture loader would add a framework and decide the pixel format and premultiplication
  for us, and it needs a device, so it could not be tested headlessly.

**Alternatives considered**: `MTKTextureLoader` (above); reading the PNG's raw, non-premultiplied
16-bit samples through the data provider (byte order and colour-space handling by hand, for no gain).

## R3 — Colour and blending: what "as designed over black" means

**Decision**: Upload the premultiplied, sRGB-encoded bytes to an `.rgba8Unorm_srgb` texture. Sampling
decodes the colour to linear and leaves alpha alone. Draw with blend factors `one` and
`oneMinusSourceAlpha` into the `.bgra8Unorm_srgb` surface. Over black this stores exactly the encoded
premultiplied value `α·c` for each pixel, the same result Core Graphics gives when it draws the image
over black. That is the testable meaning of FR-004: "its colour weighted by its alpha", with zero alpha
leaving black untouched.

**Rationale**:
- It matches how design tools and the system show the file over black, which is the same choice 002
  made for text (002 research R4: match the system rather than a physically linear blend).
- No shader maths: the texture format does the decode, the blend state does the rest.
- Filtering premultiplied values is correct at the edges: no dark or light fringe (User Story 1,
  scenario 3), which unpremultiplied bilinear filtering would produce.

**Alternatives considered**: a non-sRGB texture with manual decode in the fragment shader (same result,
more code); linear-space premultiplication (brighter anti-aliased edges than the design, as 002 found
for text).

## R4 — The texture: created once, with a mip chain made once

**Decision**: `ShipSprite` (rendering layer, GPU side) creates one 80 × 80 `.rgba8Unorm_srgb` texture
with the full mip chain (7 levels: 80, 40, 20, 10, 5, 2, 1), default storage mode, `.shaderRead`. It
uploads level 0 with `replace(region:)` and fills the other levels with one blit `generateMipmaps` in a
single command buffer, committed and awaited during renderer initialisation. The fragment shader samples
with a `constexpr` sampler: linear min/mag, linear mip filter, `clamp_to_zero`.

**Rationale**:
- At 2× and quarter turns, surface pixel centres fall on texel centres (R6), so linear filtering returns
  each texel exactly: pixel-exact as FR-010 requires.
- At 1× the image is shown at half size. Trilinear filtering reads the 40 × 40 level, which is a proper
  downscale, so a spinning ship does not shimmer. At 3× it is magnified and bilinear is smooth.
- The mip chain costs about 25 KB once. A `constexpr` sampler needs no sampler-state object and no
  failure path, as with text.
- `clamp_to_zero` makes anything sampled outside the image transparent, so the quad's edge can never
  show a smeared border.

**Alternatives considered**: no mipmaps (bilinear at 2:1 is an exact box filter when axis-aligned, but
aliases when rotated); CPU-resampled levels (more code, resampled in encoded space); a sampler-state
object (an extra failure mode for no benefit).

## R5 — Geometry: four corners computed on the CPU, passed inline

**Decision**: A pure value, `ShipSpritePlacement`, computes the ship's four corners for a pose on a
surface, in surface pixels and in clip space (the contract is in
[contracts/ship-sprite.md](./contracts/ship-sprite.md)). Each frame the renderer converts the clip
corners to four `SIMD2<Float>` and passes those 32 bytes with `setVertexBytes`. The vertex shader picks
the corner and its texture coordinate from `vertex_id` in triangle-strip order. There is no vertex
buffer to create or refill.

**Rationale**:
- What the tests check is exactly what is drawn: the shader does no placement maths of its own (FR-017).
- `setVertexBytes` copies small data into the command stream: no buffer to create, no per-frame
  allocation, and no CPU/GPU race on a shared buffer that would need text's slot ring (FR-011).
- Double precision on the CPU and conversion to `Float` last, so large world coordinates lose precision
  only once they are far off screen.

**Alternatives considered**: a unit quad plus a transform uniform (the placement maths would live in the
shader, untested); a per-frame vertex buffer (needs triple buffering, as text does).

## R6 — Placement maths: points, snapped pixels, then clip

**Decision** (normative in the contract):
1. `camera = Camera(surface:)`. No camera means no placement (FR-012).
2. Centre in view points `v = camera.view(fromWorld: position)`, then in surface pixels
   `c = (v.x·s, v.y·s)` rounded to the nearest whole pixel (`.toNearestOrAwayFromZero`), with `s` the
   backing scale (FR-006a).
3. Half-size in pixels `k = GameSpace.shipLength / 2 · s` (20·s: 20, 40 and 60 px at 1×, 2× and 3×).
4. In pixel space (+y down), the image's up direction (towards the ship's front) is `f = (cos h, −sin h)`,
   and the image's right direction is `r = (sin h, cos h)`. This is FR-007's rotation by (h − π/2),
   counter-clockwise in world space, with y flipped for pixels.
5. Corners: top-left `c + k·f − k·r`, top-right `c + k·f + k·r`, bottom-left `c − k·f − k·r`,
   bottom-right `c − k·f + k·r`.
6. Clip: `x = px / W · 2 − 1`, `y = 1 − py / H · 2`, with W × H the surface in pixels.

**Rationale**: At h = 0, `f = (1, 0)` so the image's top points right, and `r = (0, 1)` so its right
side points down: a quarter turn clockwise, as 005 FR-010 records. The rotation is built from the
world-space angle and flipped once for pixels, the trap the `GameSpace` note warns about. Every corner
is exactly `k` along each axis from `c`, so the shape is a square at any heading (FR-008). Because `c`
is a whole pixel and `k` is a whole number at 1×, 2× and 3×, the corners are whole pixels at quarter
turns, and surface pixel centres meet texel centres (FR-010).

**Wrap point**: the heading is used only through `cos` and `sin`, so π and just above −π give the same
corners: no jump at the wrap (edge case).

**Alternatives considered**: snapping only when axis-aligned (a visible one-pixel hop as the ship
turns past a quarter); computing in clip space directly (the aspect ratio must then be undone by hand,
which is exactly the stretching bug User Story 3 guards against).

## R7 — Failure: one new `RendererError` case

**Decision**: Add `RendererError.shipImageUnavailable(reason: String)` with diagnostic code
`ship_image_unavailable`. Its user-facing description says the ship image could not be loaded and that
the installation may be incomplete, followed by the reason. Missing file, undecodable data, wrong size,
texture creation failure and mip-generation failure all map to it, with different `reason` text (FR-005).
`ShipImageBitmap` throws its own small `ShipImageError`. The renderer converts it, as `TextRenderer`'s
errors are handled separately from the quad's.

**Rationale**: One stable code for "the ship image is not usable", as the spec asks (User Story 4,
scenario 2), while the reason still tells a developer which step failed. The FR-024 notice and FR-026
diagnostic paths already render any `RendererError`, so the platform layer does not change.

**Alternatives considered**: separate cases per cause (the spec asks for one code); treating the ship
like text, as non-fatal (the ticket makes it fatal: an invisible ship is not a working game).

## R8 — Draw order and the render pass

**Decision**: One pass, as now: black quad, then ship (if there is a camera and the ship is not hidden
by `--no-ship`), then text. The ship's pipeline is a second `MTLRenderPipelineState` with blending
enabled. The quad's pipeline is unchanged and still draws opaque black first (001 FR-002a).

**Rationale**: FR-009's order falls out of encoding order. The quad keeps covering every pixel, so
nothing about the black background, or the 001 checks on it, changes.

## R9 — Debug switches: `--debug-ship-spin` and `--no-ship`

**Decision**: A Debug/Profiling-only `DebugShipOptions` value in `GameSurfaceView.swift`, beside
`DebugTextMode`, parses `--debug-ship-spin` and `--no-ship` independently of each other and of the text
arguments. `--no-ship` sets `renderer.drawsShip = false` (a `SWIFTSKY_INSTRUMENTATION`-only property,
default `true`). `--debug-ship-spin` sets `FrameLoop.debugShipSpin = true` (also instrumentation-only)
before the loop starts. The loop then advances with
`Simulation.advance(state, ticks: ticks, input: ControlInput(thrust: 0, turn: 1))`, the existing
explicit-input entry point that leaves any order alone (006). All of it, argument strings included, is
compiled out of Release (FR-015).

**Rationale**:
- The platform layer already chooses the simulation's input each frame and already parses Debug-only
  arguments; this reuses both paths. The logic layer does not change.
- A full turn input makes the ship reach its maximum rate of π rad/s after 0.5 s of angular
  acceleration, then hold it: one turn every 2 s (SC-004), counter-clockwise.
- `--no-ship` hides the drawing only (FR-014), so it cannot perturb the simulation's determinism.

**Alternatives considered**: a debug move order (the ship would fly away from the centre, which makes
rotation harder to judge); a new logic-layer "spin" mode (a debug concept in the logic layer, rejected
by Principle I).

## R10 — Performance and allocation

**Decision**: The per-frame ship work is: one `Camera` (a 16-byte value), one `ShipSpritePlacement`
(a value of doubles), `cos` and `sin`, one `setRenderPipelineState`, one `setVertexBytes` of 32 bytes,
one `setFragmentTexture` and one four-vertex draw. None of it allocates. Evidence comes from the existing
Debug instrumentation (allocation count and frame times, 001 FR-021d), measured with the ship drawn and
compared against 003's recorded baseline (Principle III before/after).

## R11 — Loose ends in existing text

**Decision**: Update doc comments that say the renderer draws nothing from the ship until SKY-27
(`SimulationState`), the `GameSpace` note (it now points at the implementation), the shader file's
header (it no longer draws only black), `DebugTextMode`'s note that `--no-debug-overlay` leaves a
uniformly black surface (now true only with `--no-ship`), and `CLAUDE.md`.
