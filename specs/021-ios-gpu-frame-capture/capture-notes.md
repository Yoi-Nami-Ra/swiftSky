# Capture notes: iOS GPU Frame Capture Check (SKY-18)

Filled from the output of [probe.sh](probe.sh), following [quickstart.md](quickstart.md). Fields and
expected values are in [data-model.md](data-model.md) "Probe run". Text only; nothing else is committed.

## Header

- T001 verify result (`./Scripts/verify.sh`, branch `021-ios-gpu-frame-capture`, 2026-10-18): VERIFICATION PASSED, all stages green (exit 0)
- Date of run: _(to fill)_
- Xcode version: _(to fill)_
- Build: _(to fill)_ (expected: Debug)
- Launch arguments: _(to fill)_ (expected: `--no-ship --no-debug-overlay`)
- Simulator (model, UDID, OS): _(to fill)_
- Failure notice shown at launch (yes/no): _(to fill)_

## Counts (10 s)

- presents: _(to fill)_
- draws: _(to fill)_
- pipeline bindings: _(to fill)_
- viewport changes: _(to fill)_
- pipeline-state creations: _(to fill)_
- buffer creations: _(to fill)_

## Sample 1

- thread: _(to fill)_
- pipeline address, label: _(to fill)_
- vertex buffer address, label, offset, index, length: _(to fill)_
- vertex buffer floats: _(to fill)_
- draw primitive type, start, count: _(to fill)_

## Sample 2 (5 s later, same run)

- thread: _(to fill)_
- pipeline address, label: _(to fill)_
- vertex buffer address, label, offset, index, length: _(to fill)_
- vertex buffer floats: _(to fill)_
- draw primitive type, start, count: _(to fill)_
- same pipeline and buffer addresses as sample 1: _(to fill)_
