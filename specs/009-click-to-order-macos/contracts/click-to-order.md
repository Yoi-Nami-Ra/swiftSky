# Contract: Click to Order

**Feature**: `009-click-to-order-macos` | **Spec**: [../spec.md](../spec.md)

## ClickPosition

```swift
enum ClickPosition {
    static func viewPoint(fromBottomLeft position: Vector2, heightPoints: Double) -> Vector2  // (x, h − y)
}
```

| # | Guarantee | Spec |
|---|-----------|------|
| C1 | On a w × h point surface, the bottom-left (0, 0), top-left (0, h), top-right (w, h) and bottom-right (w, 0) give view positions (0, h), (0, 0), (w, 0) and (w, h); the centre gives (w/2, h/2) | FR-004 |
| C2 | Through `MoveOrderRequest.apply`, those five give world points (−w/2, −h/2), (−w/2, h/2), (w/2, h/2), (w/2, −h/2) and (0, 0) within 1e-9, on 1,280 × 800, 800 × 1,280, 1,001 × 667 and 1,512 × 982 point surfaces at 1× and 2× | SC-002, US3-1 |
| C3 | The same click on the same size in points gives the identical world point at 1× and 2× | US3-2 |
| C4 | A click in the upper half gives positive world y and one in the lower half negative: never mirrored | US1-3 |
| C5 | Fractional positions (e.g. (100.25, 50.5)) pass through exactly: x unchanged, y = h − 50.5 | FR-004 |

## MetalSurfaceView (macOS)

| # | Guarantee | Spec |
|---|-----------|------|
| C6 | One `NSClickGestureRecognizer`, `buttonMask = 0x1`, one click; its action posts `.moveOrderRequested(MoveOrderRequest(viewPoint: ClickPosition.viewPoint(fromBottomLeft: location(in: self), heightPoints: bounds.height)))` | FR-001, FR-004, FR-006 |
| C7 | The action posts nothing when Control is held; Command, Option and Shift do not prevent the order | FR-001, clarification |
| C8 | `acceptsFirstMouse(for:)` returns `false`, so the first click on an inactive window only activates it | FR-003, clarification |
| C9 | No change to the order request, the frame loop, `SurfaceEvent`, the logic layer, the rendering layer or the iOS code | FR-007 |
| C10 | The accessibility element, role and label are unchanged | FR-009 |
