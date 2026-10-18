# Feature Specification: iOS GPU Frame Capture Check

**Feature Branch**: `021-ios-gpu-frame-capture`

**Created**: 2026-10-18

**Status**: Draft (amended 2026-10-18: lldb verification replaces the hand capture)

**Input**: User description: "SKY-18 — Verify draw call via GPU frame capture on iOS. Quickstart checks 4
(SC-019, FR-002a) and 5 (FR-002b) of specs/001-metal-app-shell are open; they need Xcode's interactive
GPU debugger. Capture a frame of the iOS app and confirm: (1) each frame contains a shader-backed draw
call covering the surface, not a clear-only pass (check 4); (2) the pipeline state and vertex buffer are
created once at init and reused every frame, not rebuilt (check 5; structural evidence is in
FullscreenQuad). Record the result in the quickstart. The macOS capture is SKY-19."

## Clarifications

### Session 2026-10-18

- Q: How are the iOS frames observed? → A: Automatically, with lldb attached to the running Debug app in
  the simulator: breakpoints on Metal's own calls count and read every draw, binding and object
  creation over a run of frames. No code is added to the app. (This replaces the earlier answer "by
  hand in Xcode's GPU debugger": the hand capture could not be automated, and the lldb run observes the
  same command stream with exact values.)
- Q: Does an observation in the iOS Simulator close the checks, or is a physical device needed? → A:
  The simulator closes them _(assumed — specs/001-metal-app-shell/quickstart.md:116–137, check 2 closed
  on the simulator in SKY-16)_
- Q: What happens if a check fails? → A: It is recorded as FAIL and a bug ticket is filed; the fix is
  a separate ticket _(assumed — check 33's Dynamic Type FAIL became SKY-38,
  specs/001-metal-app-shell/quickstart.md:735)_
- Q: In what form is the evidence kept? → A: As text in 001's quickstart, with the lldb commands that
  reproduce it; no capture files or screenshots are committed _(assumed — `git ls-files specs` holds
  only Markdown and one patch; checks 2, 25 and 29 were recorded as text)_
- Q: Which build is observed? → A: Debug, launched with `--no-ship --no-debug-overlay` _(assumed —
  SKY-16's check 2 used the same build and arguments, specs/001-metal-app-shell/quickstart.md:116–117)_
- Q: Does an lldb observation satisfy check 4's "capture a frame in the GPU debugger"? → A: Yes; the
  record says the check was verified with lldb instead of the GPU debugger and why that settles it
  (the user chose this method on 2026-10-18).

## User Scenarios & Testing *(mandatory)*

This feature closes two checks that 001-metal-app-shell left open on iOS. It adds no behaviour to the
app: the deliverable is evidence, gathered by a scripted debugger session and written into 001's
quickstart, that the iOS app draws what 001 says it draws.

### User Story 1 - Observe the full-surface draw in every frame (Priority: P1)

A developer (or the session) runs the iOS app in the simulator with a debugger attached, and observes
that every presented frame encodes a draw that runs the full-screen quad's pipeline over geometry
spanning the whole surface, rather than a render pass that only clears the surface to black.

**Why this priority**: It is the claim 001 exists to prove (FR-002a, SC-019), and the only one of the
two checks that cannot be argued from the code alone.

**Independent Test**: Run the counting probe and the sampling probe in [quickstart.md](quickstart.md)
against the Debug app with the ship and debug overlay off.

**Acceptance Scenarios**:

1. **Given** the iOS app running with the ship and the debug overlay switched off, **When** the draws,
   pipeline bindings and presents are counted over at least 5 seconds, **Then** there is one draw and
   one quad pipeline binding per presented frame (allowing one frame in flight at the edges).
2. **Given** the same run, **When** one frame's pipeline binding, vertex-buffer binding and draw are
   read, **Then** the pipeline is labelled `swiftSky.fullscreenQuad`, the vertex buffer
   `swiftSky.quadVertices` holds the four clip-space corners (−1, −1), (1, −1), (−1, 1), (1, 1), and the
   draw is a 4-vertex triangle strip from vertex 0.
3. **Given** the same run, **When** viewport changes are counted, **Then** there are none, so the
   default viewport (the whole colour attachment, which is the drawable) applies and the strip covers
   every pixel. (The final colour cannot show this: the pass is cleared to black and the quad also draws
   black.)

---

### User Story 2 - Confirm the quad's pipeline and geometry are built once (Priority: P2)

The same debugger session confirms that no frame creates a pipeline state or a buffer, and that the
quad's pipeline and vertex buffer are the same objects in two frames at least 5 seconds apart.

**Why this priority**: FR-002b is already supported by the code's structure; the observation turns
that structural argument into evidence, which closes check 5.

**Independent Test**: Run the two probes in [quickstart.md](quickstart.md) and compare the counts and
the two samples' object addresses.

**Acceptance Scenarios**:

1. **Given** the app running after launch, **When** pipeline-state and buffer creation calls are
   counted over at least 5 seconds of frames, **Then** both counts are zero.
2. **Given** two samples at least 5 seconds apart in one run, **When** the bound pipeline and vertex
   buffer addresses are compared, **Then** they are equal.

---

### User Story 3 - Record the result where 001 tracks its checks (Priority: P3)

The outcome of checks 4 and 5 for iOS is recorded in 001's quickstart, so the next reader of that file
sees which checks remain open and why.

**Why this priority**: Without the record the observation is lost; it is cheap once stories 1 and 2
are done.

**Independent Test**: Read 001's quickstart: checks 4 and 5 carry a dated iOS result with what was
observed and how, and its summary of open checks no longer lists their iOS half.

**Acceptance Scenarios**:

1. **Given** stories 1 and 2 are done, **When** 001's quickstart is read, **Then** checks 4 and 5 each
   have a dated iOS result (PASS or FAIL) naming the build, the destination, the method (lldb) and what
   was observed.
2. **Given** that record, **When** the open-checks summary is read, **Then** it says
   that checks 4 and 5 remain open for macOS only (SKY-19), or are no longer open if SKY-19 has
   already recorded its half.

### Edge Cases

- lldb cannot attach to, or break in, the simulator app: the session stops and reports it; the hand
  capture in Xcode's GPU debugger is the fallback, and the developer decides.
- The observation shows a frame with no quad draw, a different geometry, or a viewport change: the
  check is recorded as FAIL with what was seen, and a bug ticket is filed; fixing it is not part of
  this feature.
- A pipeline state or buffer is created while frames run: check 5 is recorded as FAIL in the same way,
  with the creating call's backtrace.
- The app shows the startup failure notice instead of the surface: the observation does not count;
  the check needs the surface running normally.
- Breakpoints slow the frame rate; this does not affect what is encoded per frame, and frame rate is
  not part of either check.
- The probe attaches after launch, so it does not see the initial creation of the quad's objects;
  their creation at initialisation is shown by the code (`Renderer.swift`, in `init`) and their
  constancy by the observation.
- SKY-19 has already recorded the macOS half when this one is recorded: the open-checks table drops
  checks 4 and 5 entirely rather than listing them as macOS-only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The check MUST be made on a build that runs the same rendering path as a shipped build,
  with launch options that switch off the ship and the debug overlay available, so the quad's draw can
  be seen on its own.
- **FR-002**: The iOS app's frames MUST be observed with lldb attached to the running app in the
  simulator, using breakpoints on Metal's own calls, by the commands in quickstart.md. No code is added
  to the app.
- **FR-003**: Check 4 MUST pass only when, over at least 5 seconds of frames, every presented frame has
  a draw bound to the pipeline labelled `swiftSky.fullscreenQuad` and the buffer labelled
  `swiftSky.quadVertices`; the sampled draw is a 4-vertex triangle strip from vertex 0 over the four
  clip-space corners; and no viewport is set. The final colour is not evidence: the clear and the quad
  are both black.
- **FR-004**: Check 5 MUST pass only when no pipeline state or buffer is created over at least 5 seconds
  of frames, and two samples at least 5 seconds apart in one run bind the same pipeline and vertex
  buffer addresses.
- **FR-005**: The result of each check MUST be recorded in specs/001-metal-app-shell/quickstart.md
  under that check, dated, naming the build configuration, the destination (simulator model and OS
  version), the method (lldb, with a pointer to this feature's quickstart) and what was observed. The
  record is text; no capture files or screenshots are committed.
- **FR-006**: The quickstart's open-checks summary MUST be updated to match the recorded results, as
  earlier closings were: a dated sentence above the open-checks table (the original count stays as
  written), and the table rows for checks 4 and 5 changed to macOS only under SKY-19, or removed if
  that half is already recorded.
- **FR-007**: A failed check MUST be recorded as FAIL with what was seen, and a bug ticket MUST be filed
  for it in the project's backlog; the fix is out of scope for this feature.
- **FR-008**: The feature MUST NOT change the app's rendering code. Any change found necessary goes to
  a separate ticket.

### Key Entities

- **Probe run**: one attached debugger session over the running app: the counts of draws, pipeline
  bindings, presents, viewport changes and object creations, and two samples of the bound pipeline,
  vertex buffer (address, label, length, contents) and draw arguments.
- **Check record**: the dated entry under a quickstart check: result, build, destination, method and
  the observations that support it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Checks 4 and 5 of 001's quickstart each carry a recorded iOS result, so the number of
  checks open on iOS falls by two.
- **SC-002**: A reader of the record can tell, without repeating the run, which draw covers the
  surface, which pipeline and geometry it uses, that no objects were created per frame, and that the
  same objects were seen in both samples — and can repeat the run from the commands given.
- **SC-003**: The run needs no person at the keyboard and takes under 10 minutes including the build.
- **SC-004**: The app's rendering code is unchanged by this feature.

## Assumptions

- lldb can attach to a simulator app launched with `xcrun simctl launch` and break in Metal's
  serializer layer (`MTLSerializerRenderCommandEncoder`); this was confirmed on 2026-10-18 with Xcode
  27.0 (27A266a) and an iPhone 18 Pro simulator on iOS 27.0.
- The Debug build is used, since it carries the launch options `--no-ship` and `--no-debug-overlay`
  (as in SKY-16's check 2).
- The full-screen quad's pipeline and vertex buffer carry debug labels that identify them
  (`FullscreenQuad.swift`).
- An observation in the iOS Simulator closes the checks, as the simulator closed check 2 (SKY-16).
- With the ship and debug overlay off and no order given, the order overlay draws nothing, so the quad
  is the only draw in the pass.
- The macOS half of checks 4 and 5 is SKY-19 and is not done here. The probe is iOS-simulator only (`simctl`,
  the iOS scheme, the simulator's `MTLSerializerRenderCommandEncoder`); macOS needs its own variant of
  the same breakpoints, or a capture.
