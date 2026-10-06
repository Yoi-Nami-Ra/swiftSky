# Implementation Plan: CI Running the Verification Script

**Branch**: `018-ci-verify-workflow` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/018-ci-verify-workflow/spec.md`

## Summary

`Scripts/verify.sh` becomes the CI job body, unchanged. One GitHub Actions workflow,
`.github/workflows/verify.yml`, runs on pushes to `main` and on pull requests against `main`, on a
self-hosted runner on this Mac labelled `self-hosted`, `macOS`, `xcode-27`, with two steps: checkout and
the script. `.github/RUNNER.md` documents installing, starting, stopping and checking the runner and the
merge rule. 001's plan and CLAUDE.md stop recording the absence of CI. The remote already exists and
`main` is pushed (R1).

Everything that acts on GitHub or installs a service — registering and starting the runner, pushing,
opening pull requests, the red-check demonstration — is a developer step in
[quickstart.md](./quickstart.md) (FR-012). This plan's implementation writes files and runs local checks
only.

**Technical approach** (decision record in [research.md](./research.md)):
- **Triggers** (R2): push to `main`, pull requests against `main`.
- **Job** (R3): `runs-on: [self-hosted, macOS, xcode-27]`, `timeout-minutes: 30`,
  `permissions: contents: read`, `actions/checkout@v7` with `persist-credentials: false`, then
  `./Scripts/verify.sh`.
- **Superseded runs** (R4): a concurrency group per pull request with cancel-in-progress, and a group
  per run on `main` so no `main` run is ever cancelled or dropped.
- **Clean workspace** (R5): checkout's default clean, so every run starts as a clean clone.
- **Runner** (R6): `~/actions-runner/swiftSky`, registered to the repository with `--labels xcode-27`,
  run as a LaunchAgent through the runner's `svc.sh` under the developer's user.
- **Merge gate** (R8): written rule, recorded below as procedural.
- **Local validation** (R9): `actionlint` on the workflow, not added to `verify.sh`.

## Technical Context

**Language/Version**: GitHub Actions workflow YAML; POSIX `sh` (the unchanged `verify.sh`). The app
code (Swift 6.4) is not touched.

**Primary Dependencies**: GitHub Actions; `actions/checkout@v7`; the GitHub Actions runner (macOS ARM64,
self-updating); Xcode 27.0 (27A266a) with the Metal toolchain, already on this Mac.

**Storage**: N/A.

**Testing**: No new automated tests: the feature adds no logic (Principle II applies to logic). The
workflow is checked with `actionlint` locally (L2) and by real runs (D2–D6). `./Scripts/verify.sh` must
still pass (L3).

**Target Platform**: This Mac (Apple silicon, macOS 26) as the CI runner; the repository on GitHub.

**Project Type**: Repository infrastructure for the existing cross-platform app.

**Performance Goals**: A CI run takes about as long as a clean local `verify.sh` run (SC-002); 30-minute
hard limit (FR-007).

**Constraints**: Exactly two steps (FR-004); `verify.sh` behaviour unchanged (FR-005); no agent action
on GitHub or on this Mac's services (FR-012); repository stays private (spec Assumptions).

**Scale/Scope**: 2 new files (`.github/workflows/verify.yml`, `.github/RUNNER.md`); 3 edited
(`specs/001-metal-app-shell/plan.md`, `CLAUDE.md`, `Scripts/verify.sh` comment only). No change to
`Package.swift`, sources, tests or the Xcode project.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Architecture Discipline | **PASS** (N/A) | No source code changes; the layers are untouched. |
| II. Test Coverage Discipline | **PASS, with a recorded gap** | This feature is what Principle II asks for once a remote exists: the single checked-in command (`verify.sh`) is wired into CI and runs on every push to `main` and every pull request. The clause "MUST gate merges" is met procedurally (FR-014) rather than by branch protection, which the ticket leaves out; recorded in Complexity Tracking. No logic is added, so no new tests are owed. |
| III. Performance & Resource Efficiency | **PASS** (N/A) | No runtime code changes. CI time is bounded (30 min) and measured (SC-002). |
| IV. Accessibility & Platform UX | **PASS** (N/A) | No UI. |
| V. Simplicity & YAGNI | **PASS** | Two steps, no caching, no matrix, no dispatch trigger, no artefacts. The concurrency block (R4) is the one addition beyond the ticket's minimum, and it exists because there is a single runner. |

**Post-design re-check** (after research, data model, contract and quickstart): unchanged — all PASS,
one recorded gap (procedural merge gate).

## Project Structure

### Documentation (this feature)

```text
specs/018-ci-verify-workflow/
├── plan.md              # This file
├── research.md          # Phase 0: R1–R10
├── data-model.md        # Phase 1: workflow, runner, job result
├── quickstart.md        # Phase 1: local checks L1–L4, developer checks D1–D6
├── contracts/
│   └── verify-workflow.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
.github/
├── workflows/
│   └── verify.yml       # NEW — the CI workflow (contract: contracts/verify-workflow.md)
└── RUNNER.md            # NEW — install, start, stop, check, remove the runner; merge rule
Scripts/
└── verify.sh            # header comment only: it is now the CI job body
specs/001-metal-app-shell/
└── plan.md              # CI-absence record removed; Principle II rows cite 018
CLAUDE.md                # CI described as present; key location for the workflow and RUNNER.md
```

**Structure Decision**: The workflow lives where GitHub requires it. The runner's operating notes sit
beside it in `.github/` because they are standing documentation for the repository, not history of
this spec; the quickstart links to them rather than repeating them.

## Complexity Tracking

> Principle II gap recorded, as the constitution asks for any principle not fully met.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **Merge gate is procedural, not enforced** — Principle II says CI "MUST gate merges"; here a written rule (FR-014: no merge while `verify / verify` is red, cancelled or missing) stands in for a host-enforced required check | The ticket puts branch protection out of scope, and protection rules on a private repository depend on the account's plan, which this feature does not change | **Branch protection / a ruleset requiring `verify / verify`** is the enforced gate and the obvious follow-up; it is a GitHub settings change for the developer, outside this ticket. Until then every pull request shows the result, and the rule is in `.github/RUNNER.md` and CLAUDE.md. |
