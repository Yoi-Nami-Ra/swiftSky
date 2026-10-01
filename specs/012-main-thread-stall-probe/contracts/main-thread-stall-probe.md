# Contract: Main-Thread Stall Probe

## C1 — Summary format

The frame summary (001 FR-021d, 011 R9) gains two fields at its end, in both of its forms:

```text
… gfxallocs=<n> mainworst=<ms>ms mainover=<n>
… allocs=unavailable mainworst=<ms>ms mainover=<n>
```

- `mainworst` — the longest main-thread busy stretch that **ended** since the previous summary (or since
  the last restart), in milliseconds, formatted like `worst=`. `0` if none ended.
- `mainover` — how many of those stretches were longer than the frame interval in force when each ended.
- Existing fields keep their names, order and meaning.

## C2 — Measurement

- A busy stretch runs from the main run loop's after-waiting to its next before-waiting, in every common
  mode (default, event tracking, modal panel).
- Waiting is never busy.
- A stretch belongs to the summary in which it ends.
- Both figures restart after each summary and whenever the frame budget is relearned.

## C3 — Cost

- Main thread: two clock reads and one compare-and-exchange loop per run-loop pass. No allocation, no
  lock, no blocking.
- Frame loop thread: one `exchange` per summary and per restart. Nothing on other frames.
- Release builds contain none of it (no `mainworst=`, `mainover=`, `live resize`, `--debug-main-stall`, or
  `MainThreadStallProbe` symbol).

## C4 — Live-resize markers (macOS)

`live resize began` and `live resize ended`, `notice`, subsystem `com.swiftsky.app`, category `frame`,
once each per drag. The summaries **covering a drag** are those written after `live resize began`, up to
and including the first one written after `live resize ended`.

## C5 — Deliberate stall

`--debug-main-stall` (instrumented builds): once, 5 s after launch, the main thread spins for 50 ms.

## C6 — PASS rules (check 29)

- **Race half** (Thread Sanitizer build, ≥ 10 s continuous drag): zero `WARNING: ThreadSanitizer: data
  race` reports, and summaries keep being written throughout the drag.
- **Stall half** (optimised instrumented build, 011 R12, ≥ 10 s continuous drag): every summary covering
  the drag has `mainover=0` and `mainworst` ≤ its own `budget=`. The first summary of a run and the first
  after a `budget=` change are start-up summaries and are excluded unless they cover the drag; a drag is
  started only after the second summary has been written.
- Any overrun is a FAIL. Its source is found with `sample <pid>` during a repeat; a cause wholly in system
  code is recorded as a FAIL with the sample and a follow-up ticket (spec Clarifications).
