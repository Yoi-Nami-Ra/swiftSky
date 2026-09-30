# Contract: Live Debug Overlay

**Feature**: [../spec.md](../spec.md) | **Data model**: [../data-model.md](../data-model.md)

The seams this feature adds or changes. Everything marked *(instrumentation)* exists only when
`SWIFTSKY_INSTRUMENTATION` is defined: Debug and Profiling builds (FR-009).

## Rendering layer: text buffer (added, all builds)

```swift
extension TextBuffer {
    /// `value` rounded half away from zero to two decimal places, right-aligned in `width` columns
    /// with spaces, written in full when wider. Negative or NaN → "0.00". Allocates nothing.
    public func writeHundredths(_ value: Double, width: Int = 0, limit: Int = .max)

    /// A literal right-aligned in `width` columns. Allocates nothing.
    public func writePadded(_ text: StaticString, width: Int, limit: Int = .max)
}
```

| Input | `width: 6` output |
|-------|-------------------|
| `0` | `  0.00` |
| `0.004` | `  0.00` |
| `0.005` | `  0.01` |
| `8.333` | `  8.33` |
| `16.667` | ` 16.67` |
| `999.994` | `999.99` |
| `1234.5` | `1234.50` (wider than 6, written in full) |
| `-1`, `.nan` | `  0.00` |

## Rendering layer: overlay *(instrumentation)*

```swift
public struct DebugOverlayStatistics: Sendable, Equatable {
    public var meanFrameSeconds: Double?
    public var worstFrameSeconds: Double?
    public var budgetSeconds: Double
    public var droppedFrames: UInt64
    public var skippedFrames: UInt64
    public var tickCount: UInt64
}

public final class DebugOverlay {
    public init()
    public var statistics: DebugOverlayStatistics?
    public func write(into buffer: TextBuffer, surface: RenderSurface)
}

// Members of `Renderer`, inside its `#if SWIFTSKY_INSTRUMENTATION` block:
public var debugOverlay: DebugOverlay?                                // set once, before the loop starts
public func updateDebugOverlay(_ statistics: DebugOverlayStatistics)  // loop thread only
```

`Renderer.prepareText` clears the text buffer, then writes `debugTextPattern` if set, otherwise
`debugOverlay` if set. Platform parsing guarantees that at most one is set (FR-012).
`DebugOverlay.write` never clears the buffer itself.

### Overlay text

Anchored at `(safeAreaInsets.left + 8, safeAreaInsets.top + 8)` points (FR-003). There are six lines.
Each label is exactly 8 columns, including its trailing spaces:

| Line | Label | Value |
|------|-------|-------|
| 1 | `mean    ` | `writeHundredths(ms, width: 6)` + ` ms`, or `writePadded("--", width: 6)` + ` ms` |
| 2 | `worst   ` | the same |
| 3 | `budget  ` | `writeHundredths(budget ms, width: 6)` + ` ms` |
| 4 | `dropped ` | `write(UInt64)` |
| 5 | `skipped ` | `write(UInt64)` |
| 6 | `ticks   ` | `write(UInt64)` |

Example, 120 Hz display, one second in:

```text
mean      0.41 ms
worst     0.97 ms
budget    8.33 ms
dropped 0
skipped 0
ticks   61
```

## Platform layer: instrumentation *(instrumentation)*

```swift
struct FrameTimeWindow       { mutating func record(frameSeconds: Double); mutating func closeBucket()
                               mutating func restart(); var mean: Double? { get }; var worst: Double? { get } }
struct OverlayRefreshSchedule { static let refreshRate = 4.0; static let interval: Double
                               mutating func isDue(at timestamp: Double) -> Bool; mutating func restart() }

extension Instrumentation {
    mutating func overlayStatistics(at timestamp: Double) -> DebugOverlayStatistics?
    mutating func restartOverlayWindow()
}
```

## Platform layer: frame loop (changed)

Per frame, the order in 001's `contracts/frame-loop.md` gains one step. It sits between the clock read
(3) and the simulation advance (4):

> **3a.** *(instrumentation)* `if let s = instrumentation.overlayStatistics(at: now) { renderer.updateDebugOverlay(s) }`

`applyPendingEvents` calls `instrumentation.restartOverlayWindow()` on `.visibilityChanged(true)`.

## Launch arguments (Debug and Profiling builds only)

| Argument | Effect |
|----------|--------|
| *(none)* | Overlay shown (FR-001) |
| `--no-debug-overlay` | Overlay hidden, and the surface uniformly black (FR-011) |
| `--debug-text` | 002 test string. Overlay hidden (FR-012) |
| `--debug-text-fill` | 002 full-capacity fill. Overlay hidden (FR-012) |

In Release none of them has any effect, because the parsing does not exist there.
