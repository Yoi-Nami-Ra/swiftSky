# Data Model: Click to Order the Ship on macOS

**Feature**: `009-click-to-order-macos` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

One new pure helper. Everything else is 008's.

## ClickPosition (new, platform layer, platform-neutral)

A namespace (`enum` with no cases) with one pure function:

| Member | Signature | Meaning |
|--------|-----------|---------|
| `viewPoint(fromBottomLeft:heightPoints:)` | `(Vector2, Double) -> Vector2` | `(x, heightPoints − y)`: a position from the surface's bottom-left corner, +y up, into view space, from the top-left corner, +y down |

No validation: any value, even non-finite, is passed through, and 008's `MoveOrderRequest.apply`
decides what it becomes.

## Click (platform glue, macOS only, not a type)

`NSClickGestureRecognizer`: primary button (`buttonMask = 0x1`), one click, on `MetalSurfaceView`.
Ignored with Control held. Its `location(in:)` (bottom-left origin) goes through `ClickPosition` with
`bounds.height`, and the result becomes `MoveOrderRequest.viewPoint`.

## Reused unchanged (008)

`MoveOrderRequest`, `MoveOrderOutcome`, `SurfaceEvent.moveOrderRequested`, the loop's handling and the
Debug `order`/`arrived` lines.
