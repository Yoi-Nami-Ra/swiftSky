# Data Model: Frame Budget That Does Not Lock Onto Stray Gaps

## DisplayIntervalLearner (platform layer, value type)

| Field | Type | Initial | Meaning |
|-------|------|---------|---------|
| `interval` | `Double` (s) | `1/60` | The budget every frame is judged against. |
| `isLearned` | `Bool` | `false` | Whether `interval` was confirmed from gaps (vs the default). |
| `candidate` | `Double?` | `nil` | A shorter gap waiting for the very next plausible gap. |
| `floor` | `Double` (s) | `1/250` | The current display's fastest interval; `1/250` when unknown. |

Constants: `tolerance = 0.05`, `fastestPlausible = 1/250`, `slowestPlausible = 1/20`,
`defaultInterval = 1/60`.

### Plausible gap

`max(fastestPlausible, floor × (1 − tolerance)) ≤ gap ≤ slowestPlausible`.

### Transitions — `observe(gap:)`

1. Gap not plausible → no change.
2. Candidate present and `|candidate − gap| ≤ candidate × tolerance` → adopt
   `max(min(candidate, gap), floor)`; clear candidate; `isLearned = true`; report it if it differs from
   `interval`.
3. Otherwise clear candidate; if `!isLearned` or `gap < interval × (1 − tolerance)`, the gap becomes the
   candidate (a gap within the tolerance agrees with the budget).

### Transitions — `forget()`

`interval = 1/60`, `isLearned = false`, `candidate = nil`; always reports `1/60` (the loop restarts its
counters, as today).

### Transitions — `setMaximumFramesPerSecond(n)`

`floor = n > 0 ? max(1/n, fastestPlausible) : fastestPlausible`; candidate cleared. If `isLearned` and
`interval < floor × (1 − tolerance)` → `forget()` and report `1/60`; otherwise no report.

## SurfaceEvent (changed)

`+ displayRateChanged(maximumFramesPerSecond: Int)` — posted by the view before a geometry event when the
screen's maximum rate differs from the last posted value.
