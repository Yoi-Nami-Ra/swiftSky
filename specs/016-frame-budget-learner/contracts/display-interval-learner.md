# Contracts: Frame Budget Learner (016)

## C1 — `DisplayIntervalLearner`

```swift
struct DisplayIntervalLearner {
    static let defaultInterval: Double      // 1/60
    private(set) var interval: Double       // current budget, seconds
    mutating func observe(gap: Double) -> Double?            // new budget when it changed
    mutating func forget() -> Double                          // always 1/60
    mutating func setMaximumFramesPerSecond(_ n: Int) -> Double?  // 1/60 when it forgot
}
```

Rules (data-model.md): consecutive confirmation (FR-001), plausible range and floor (FR-002, FR-005),
clamped adoption (FR-003), shrink-only within a display, forget on a backing-scale change or a floor above
the budget (FR-004). No allocation, no platform imports beyond Swift (FR-006, FR-007).

## C2 — `SurfaceEvent.displayRateChanged(maximumFramesPerSecond: Int)`

- Posted by `MetalSurfaceView` on the main thread, before the geometry event of the same change, only
  when the value differs from the last one it posted (the first geometry change always posts it).
- Applied by `FrameLoop` at a frame boundary: `learner.setMaximumFramesPerSecond(n)`; a returned budget
  goes to `instrumentation.updateBudget(seconds:)`.
- `.backingScaleChanged` keeps its behaviour: `updateBudget(seconds: learner.forget())`.
- Per frame, step 3: `if let b = learner.observe(gap: elapsed) { instrumentation.updateBudget(seconds: b) }`.

## C3 — Test series (`DisplayIntervalLearnerTests`)

Gaps in ms; `h120 = 1000/120`, `h60 = 1000/60`. Floor set to the display's rate unless stated.

| # | Setup | Series | Final `interval` |
|---|-------|--------|------------------|
| 1 | floor 120 | 20 × h120 | h120 |
| 2 | floor 60 | 10 × h60, 33.33, 10 × h60 | h60 |
| 3 | floor 120, display at 60 Hz | h60 ×5, 14.84, h60 ×5, 14.84, h60 ×5 | h60 |
| 4 | floor 120, display at 60 Hz | (22.0, 11.3) × 50, interleaved with h60 | h60 |
| 5 | floor 120, display at 60 Hz | 5.0, then 20 × h60 | h60 |
| 6 | floor 120, learned h120; then `setMaximumFramesPerSecond(60)` and `forget()` | h120 ×3, 20 × h60 | h60 |
| 7 | floor 120, learned h120 | 10 × 4.17, 10 × h120 | h120 |

Plus: an unknown floor (0) with two adjacent 4.17 ms gaps adopts 4.17 ms (floor only from the display);
two adjacent 14.84 ms gaps with floor 120 adopt 14.84 ms (documented residual risk); a gap of 8.3330 ms
with floor 120 adopts exactly 1/120 s; `observe` returns `nil` when the adopted value equals `interval`.
