# Quickstart: iOS GPU Frame Capture Check

The procedure for 001's checks 4 and 5 on iOS. It is done by hand in Xcode; it takes about ten
minutes. What each observation proves is in [research.md](research.md) R2 and R3; the fields to note
are in [data-model.md](data-model.md).

## Setup

1. Open `swiftSky.xcodeproj` in Xcode 27.0. Select the iOS scheme and an iPhone simulator (a device
   only if the simulator cannot be captured, R1).
2. Edit Scheme › Run › Info: Build Configuration **Debug**. Run › Arguments: add `--no-ship` and
   `--no-debug-overlay`. Run › Options: leave GPU Frame Capture at its default (not Disabled).
3. Run (⌘R) and wait for the black surface. If the failure notice appears instead, stop: the capture
   does not count.

## Check 4 — the quad draw covers the surface

1. In the Debug bar, click the capture-GPU-workload button and capture one frame.
2. In the call list, find the render pass. Note every draw in it; with these arguments expect one.
3. Select the draw. Note its pipeline state's label (`swiftSky.fullscreenQuad`) and its vertex
   buffer's label (`swiftSky.quadVertices`).
4. Open the geometry viewer for the draw. Note the primitive (triangle strip), the vertex count (4)
   and the four positions.
5. In the attachment viewer, open the pixel history of the four corner pixels and the centre pixel.
   Note that each one lists the quad draw.

Pass: all of the above as expected. The attachment being black is not evidence: the clear is black
too.

## Check 5 — built once, reused

1. Note, in the first capture's call list, whether the frame contains any call that creates a
   render pipeline state or a buffer. Expect none.
2. In the first capture's resource list, note the pipeline and buffer with the quad's labels, how many
   of each there are (expect one), and their identity in the object inspector.
3. Continue the app for at least five seconds, capture a second frame, and repeat steps 1–2.

Pass: no creation calls in either frame, one of each object, the same identity in both captures.

## Optional — default launch

Remove the two arguments, run, capture a frame. Expect the quad draw first in the pass, with the ship
and the debug overlay's draws after it (optional; spec Edge Cases).

## Hand-off and record

Tell the session what was noted for each step (screenshots are fine to share in chat; none are
committed). The session writes the check records into `specs/001-metal-app-shell/quickstart.md` and
updates its open-checks table. On a failed step, it records FAIL and files a bug ticket.

## Repository check

```bash
./Scripts/verify.sh
```

It must still pass; the feature changes no code.
