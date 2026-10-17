# Feature Specification: iOS GPU Frame Capture Check

**Feature Branch**: `021-ios-gpu-frame-capture`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "SKY-18 — Verify draw call via GPU frame capture on iOS. Quickstart checks 4
(SC-019, FR-002a) and 5 (FR-002b) of specs/001-metal-app-shell are open; they need Xcode's interactive
GPU debugger. Capture a frame of the iOS app and confirm: (1) each frame contains a shader-backed draw
call covering the surface, not a clear-only pass (check 4); (2) the pipeline state and vertex buffer are
created once at init and reused every frame, not rebuilt (check 5; structural evidence is in
FullscreenQuad). Record the result in the quickstart. The macOS capture is SKY-19."

## User Scenarios & Testing *(mandatory)*

This feature closes two checks that 001-metal-app-shell left open on iOS. It adds no behaviour to the
app: the deliverable is evidence, taken by a developer at the keyboard and written into 001's
quickstart, that the iOS app draws what 001 says it draws.

### User Story 1 - See the full-surface draw in a captured iOS frame (Priority: P1)

A developer runs the iOS app, captures one presented frame in the GPU debugger, and finds in it a
draw that runs the app's own vertex and fragment shaders over the whole surface, rather than a render
pass that only clears the surface to black.

**Why this priority**: It is the claim 001 exists to prove (FR-002a, SC-019), and the only one of the
two checks that cannot be argued from the code alone.

**Independent Test**: Capture one frame of the iOS app with the ship and the debug overlay switched
off, and read the frame's render pass: it must hold a draw of four vertices with the full-screen quad's
pipeline, and the surface must still come out uniformly black.

**Acceptance Scenarios**:

1. **Given** the iOS app running with the ship and the debug overlay switched off, **When** a frame is
   captured, **Then** its render pass contains exactly one draw, using the full-screen quad's pipeline
   with its own vertex and fragment shaders and the quad's vertex buffer, covering the whole surface.
2. **Given** the same captured frame, **When** its final attachment is inspected, **Then** it is
   uniformly black, so the draw and not a clear produced what is on screen.
3. **Given** the iOS app running with its default launch (ship and debug overlay shown), **When** a
   frame is captured, **Then** the same full-screen quad draw is still there, first in the pass, under
   the other draws.

---

### User Story 2 - Confirm the quad's pipeline and geometry are built once (Priority: P2)

A developer captures two frames from the same run of the iOS app and confirms that both use the same
pipeline state and the same vertex buffer, and that neither frame creates them.

**Why this priority**: FR-002b is already supported by the code's structure; the capture turns that
structural argument into an observation, which closes check 5.

**Independent Test**: Capture two frames at least a few seconds apart in one run, and compare the
identity of the quad's pipeline state and vertex buffer between them.

**Acceptance Scenarios**:

1. **Given** two frames captured in one run, **When** the quad's pipeline state and vertex buffer are
   compared, **Then** they are the same objects in both frames.
2. **Given** either captured frame, **When** its recorded calls are read, **Then** it creates no
   pipeline state and no buffer for the quad.

---

### User Story 3 - Record the result where 001 tracks its checks (Priority: P3)

The developer records the outcome of checks 4 and 5 for iOS in 001's quickstart, so the next reader of
that file sees which checks remain open and why.

**Why this priority**: Without the record the captures are lost; it is cheap once stories 1 and 2 are
done.

**Independent Test**: Read 001's quickstart: checks 4 and 5 carry a dated iOS result with what was
observed, and its summary of open checks no longer lists their iOS half.

**Acceptance Scenarios**:

1. **Given** stories 1 and 2 are done, **When** 001's quickstart is read, **Then** checks 4 and 5 each
   have a dated iOS result (PASS or FAIL) naming the build, the destination and what was observed.
2. **Given** that record, **When** the open-checks table and its count are read, **Then** they say
   that checks 4 and 5 remain open for macOS only (SKY-19), or are no longer open if SKY-19 has
   already recorded its half.

### Edge Cases

- The GPU debugger cannot capture in the iOS Simulator with the installed Xcode: the capture is taken
  on a physical iOS device instead, and the record says which destination was used.
- The captured frame shows only a clear, or a draw that does not cover the whole surface: the check is
  recorded as FAIL with what was seen, and a bug ticket is filed for the defect; fixing it is not part
  of this feature.
- A captured frame creates the quad's pipeline state or vertex buffer: check 5 is recorded as FAIL in
  the same way.
- The developer captures a frame while the app shows the startup failure notice instead of the
  surface: that capture does not count; the check needs the surface running normally.
- SKY-19 has already recorded the macOS half when this one is recorded: the open-checks table drops
  checks 4 and 5 entirely rather than listing them as macOS-only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The check MUST be made on a build that runs the same rendering path as a shipped build,
  with launch options that switch off the ship and the debug overlay available, so the quad's draw can
  be seen on its own.
- **FR-002**: A frame of the iOS app MUST be captured in the GPU debugger while the surface is running
  normally.
- **FR-003**: Check 4 MUST pass only when the captured render pass contains a draw that uses the
  full-screen quad's pipeline and vertex buffer and covers the whole surface, and the surface is not
  produced by a clear alone.
- **FR-004**: Check 5 MUST pass only when two frames captured in one run use the same quad pipeline
  state and vertex buffer, and neither frame creates them.
- **FR-005**: The result of each check MUST be recorded in specs/001-metal-app-shell/quickstart.md
  under that check, dated, naming the build configuration, the destination (simulator or device, with
  its model and OS version) and what was observed.
- **FR-006**: The quickstart's open-checks table and its running count MUST be updated to match the
  recorded results, keeping the macOS half open under SKY-19 unless it is already recorded.
- **FR-007**: A failed check MUST be recorded as FAIL with what was seen, and a bug ticket MUST be filed
  for it in the project's backlog; the fix is out of scope for this feature.
- **FR-008**: The feature MUST NOT change the app's rendering code. Any change found necessary goes to
  a separate ticket.

### Key Entities

- **Captured frame**: one presented frame of the iOS app as recorded by the GPU debugger: its render
  pass, the draws in it, the pipeline state and buffers each draw uses, and the final colour attachment.
- **Check record**: the dated entry under a quickstart check: result, build, destination and the
  observations that support it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Checks 4 and 5 of 001's quickstart each carry a recorded iOS result, so the number of
  checks open on iOS falls by two.
- **SC-002**: A reader of the record can tell, without repeating the capture, which draw covers the
  surface, which pipeline and geometry it uses, and that the same objects were seen in both frames.
- **SC-003**: The capture and the record together take one developer no more than 30 minutes, given a
  working Xcode installation.
- **SC-004**: The app's rendering code is unchanged by this feature.

## Assumptions

- The capture is taken by the developer by hand: this environment cannot drive Xcode's GPU debugger
  (no Accessibility or Screen Recording permission, as 001's quickstart records).
- The Debug build is used, since it carries the launch options `--no-ship` and `--no-debug-overlay`;
  the instrumented Release build carries them too and may be used instead.
- The full-screen quad's pipeline and vertex buffer carry debug labels that identify them in the
  capture.
- The iOS Simulator is tried first; a physical device is used if the simulator cannot be captured.
- With the ship and debug overlay off and no order given, the order overlay draws nothing, so the quad
  is the only draw in the pass.
- The macOS half of checks 4 and 5 is SKY-19 and is not done here.
