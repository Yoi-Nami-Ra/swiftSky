# Research: iOS GPU Frame Capture Check

## R1 — Capturing in the iOS Simulator

**Decision**: Capture in the iOS Simulator first; use a physical iOS device only if Xcode will not
capture the simulator, and say in the record which was used.

**Rationale**: The simulator closed 001's check 2 (SKY-16), and the claim under test is about the
app's own command stream (which draws it encodes, with which objects), which the simulator records as
the app issued it. Xcode's Metal debugger captures simulator apps on Apple-silicon Macs; whether the
installed Xcode 27.0 beta does so could not be confirmed from this session (it cannot drive Xcode), so
the device is the documented fallback rather than an assumption.

**Alternatives considered**: Device only — stronger on GPU behaviour, which neither check is about,
and both test devices were last recorded as disconnected (001 quickstart, check 2).

## R2 — What proves check 4

**Decision**: Check 4 passes when the captured frame's render pass contains a draw that (a) uses the
pipeline labelled `swiftSky.fullscreenQuad` and the buffer `swiftSky.quadVertices`, (b) draws 4
vertices as a triangle strip at clip-space (−1, −1) to (1, 1), shown by the geometry viewer, with the
default viewport (the renderer sets none, so it is the whole attachment), and (c) appears in the pixel
history of the attachment's four corner pixels and its centre pixel.

**Rationale**: The pass descriptor clears to black (`Renderer.swift:128`) and the quad's fragment
shader returns black (`Shaders.metal:43–46`). A uniformly black attachment is therefore what a
clear-only pass would also produce: colour is not evidence. The presence of the draw rules out a
clear-only pass; its geometry and the pixel history show it covers the surface.

**Alternatives considered**: Temporarily changing the fragment colour to make the draw visible —
rejected, it changes the rendering code (spec FR-008) and tests a different build.

## R3 — What proves check 5

**Decision**: Take two captures in one run, at least a few seconds apart. Check 5 passes when (a)
neither frame's recorded calls include creating a render pipeline state or a buffer, (b) the
resource list of each capture holds exactly one pipeline labelled `swiftSky.fullscreenQuad` and one
buffer labelled `swiftSky.quadVertices`, and (c) the quad draw in both captures binds the same
objects (the same identity shown in the object inspector).

**Rationale**: A frame that rebuilt them would show the creation calls inside the captured frame and,
for a buffer, a second live allocation. The code already builds them once (`Renderer.swift:107`, in
`init`); the captures turn that into an observation.

**Alternatives considered**: One capture only — it shows reuse within one frame, not across frames.

## R4 — Capture settings

**Decision**: Run the iOS scheme in Debug from Xcode with arguments `--no-ship --no-debug-overlay`
(Edit Scheme › Run › Arguments), GPU Frame Capture left at its default (the project has no shared
schemes, so each developer's scheme has Xcode's default, which enables capture for Metal apps), and
capture with the Debug bar's capture-GPU-workload button. A third capture with the default launch
is optional (spec Edge Cases).

**Rationale**: The same build and arguments closed check 2 (SKY-16). Without the ship, overlay or an
order, the quad is the only draw in the pass, so it is unambiguous.

## R5 — A failed check

**Decision**: Record FAIL with what was seen, file a bug ticket with `/tickets`, leave the fix to that
ticket (spec FR-007, as check 33's Dynamic Type failure became SKY-38).
