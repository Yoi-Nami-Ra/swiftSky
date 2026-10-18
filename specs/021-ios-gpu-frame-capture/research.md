# Research: iOS GPU Frame Capture Check

## R1 — Observing in the iOS Simulator

**Decision**: Observe in the iOS Simulator; it closes the checks.

**Rationale**: The simulator closed 001's check 2 (SKY-16), and the claim under test is about the
app's own command stream (which draws it encodes, with which objects), which the simulator records as
the app issued it. lldb attaches to simulator apps and breaks in the simulator's Metal serializer
(confirmed 2026-10-18, Xcode 27.0, iPhone 18 Pro simulator, iOS 27.0).

**Alternatives considered**: Device only — stronger on GPU behaviour, which neither check is about,
and both test devices were last recorded as disconnected (001 quickstart, check 2).

## R2 — What proves check 4

**Decision** (amended 2026-10-18): check 4 passes when, with lldb attached to the running Debug app,
(a) over 10 s every presented frame has one `drawPrimitives:vertexStart:vertexCount:` and one
`setRenderPipelineState:` call (hit counts equal to the present count, ±1 for the frame in flight),
(b) a sampled frame binds the pipeline labelled `swiftSky.fullscreenQuad` and the 32-byte buffer
`swiftSky.quadVertices` at index 0 holding (−1, −1), (1, −1), (−1, 1), (1, 1), and draws primitive type 4
(`MTLPrimitiveTypeTriangleStrip`) from vertex 0, count 4, and (c) `setViewport:` is never called, so the
default viewport — the whole colour attachment, which the renderer sets to the drawable's texture — is
used, and the strip covers every pixel.

**Rationale**: The pass clears to black (`Renderer.swift:128`) and the quad's fragment shader returns
black (`Shaders.metal:43–46`), so colour is not evidence. The breakpoints sit on Metal's serializer
layer (`MTLSerializerRenderCommandEncoder`, the simulator's encoder), below the app, so they observe
exactly what the app encodes, every frame rather than one captured frame.

**Alternatives considered**: Xcode's GPU debugger by hand (the original plan) — cannot be automated
from this session, and observes one frame; changing the fragment colour — changes rendering code
(spec FR-008).

## R3 — What proves check 5

**Decision** (amended 2026-10-18): check 5 passes when no `newRenderPipelineStateWithDescriptor:…` or
`newBufferWith…` call is made over 10 s of frames, and two samples 5 s apart in one run bind the same
pipeline and vertex-buffer addresses.

**Rationale**: A renderer that rebuilt them would call the creation methods every frame. Breakpoints on
every class implementing them (27 and 45 locations) leave no other path. The probe attaches after launch,
so the creation at initialisation (`Renderer.swift:107`, in `init`) is shown by the code, and its
constancy by the observation.

## R4 — Running the probe

**Decision**: `specs/021-ios-gpu-frame-capture/probe.sh [udid]` builds the Debug iOS app, installs and
launches it with `--no-ship --no-debug-overlay` via `xcrun simctl launch`, waits 4 s, attaches
`xcrun lldb --batch`, and runs two passes: hit counts with auto-continue breakpoints over 10 s, then two
one-shot samples 5 s apart.

**Findings while building it**: attaching at launch (`simctl launch --wait-for-debugger`) stops at the
simulator's dyld notifier trap and does not resume in batch mode, and Python breakpoint callbacks
stalled the frame thread; attaching to the running app with plain auto-continue breakpoints and
`breakpoint list` hit counts works. Breakpoints slow the app to about 19 frames per second while
attached, which changes nothing that is encoded.

## R5 — A failed check

**Decision**: Record FAIL with what was seen, file a bug ticket with `/tickets`, leave the fix to that
ticket (spec FR-007, as check 33's Dynamic Type failure became SKY-38).
