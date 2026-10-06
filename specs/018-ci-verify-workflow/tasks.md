---

description: "Task list for 018-ci-verify-workflow"
---

# Tasks: CI Running the Verification Script

**Input**: Design documents from `/specs/018-ci-verify-workflow/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/verify-workflow.md, quickstart.md

**Tests**: No automated tests: the feature adds no logic (plan, Constitution Check II). Validation is the
quickstart's local checks (L1–L4) and developer checks (D1–D6).

**Organization**: By user story. Tasks marked **DEVELOPER** act on GitHub or install a service on this Mac.
Only the developer does them, by hand, following quickstart.md and `.github/RUNNER.md` (FR-012). An
implementing agent leaves them unchecked.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)

---

## Phase 1: Setup

**Purpose**: Confirm the starting state the plan relies on.

- [X] T001 Run quickstart L1 (`git remote -v`, `git config --get remote.origin.url`, `git fetch --prune && git rev-parse main origin/main`) and confirm `origin` is `Yoi-Nami-Ra/swiftSky` and `main` equals `origin/main` (FR-001, research R1); record the result under L1 in specs/018-ci-verify-workflow/quickstart.md

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: The runner's operating notes, which the developer needs before any run can happen.

- [X] T002 Write .github/RUNNER.md per research R6–R8: what the runner is (self-hosted, this Mac, repository-scoped, labels `self-hosted`, `macOS`, `ARM64`, `xcode-27`, runs as the developer's user); **Install** (folder `~/actions-runner/swiftSky`; download and checksum from *Settings → Actions → Runners → New self-hosted runner*, macOS ARM64; `./config.sh --url https://github.com/Yoi-Nami-Ra/swiftSky --token <token> --name swiftsky-<short host name> --labels xcode-27 --unattended` from a normal login shell; `./svc.sh install` then `./svc.sh start`, never with sudo); **Start / Stop / Status** (`./svc.sh start|stop|status`; fallback `./run.sh` in a terminal, Ctrl-C to stop); **Check online** (Settings runner list: Idle / Active / Offline; or `gh api repos/Yoi-Nami-Ra/swiftSky/actions/runners` as the owning account); **While the Mac is off** (jobs queue; the host cancels a job queued 24 hours; re-run it from the run page); **When Xcode changes** (change the runner label and `runs-on` in .github/workflows/verify.yml together); **Remove** (`./svc.sh uninstall`, `./config.sh remove --token <removal token>`); **Merge rule** (FR-014: no merge unless `verify / verify` passed for the pull request's current head — not while red, cancelled, queued or missing; branch protection is not set up); **Private only** (never attach this runner to a public repository)
- [ ] T003 **DEVELOPER** Quickstart D1: install, register and start the runner following .github/RUNNER.md → Install; confirm it shows Idle with all four labels and `./svc.sh status` reports it running (FR-008a, FR-009)

**Checkpoint**: The runner is online and documented.

---

## Phase 3: User Story 1 - A push to main is verified automatically (Priority: P1) 🎯 MVP

**Goal**: Every push to `main` runs `verify.sh` on this Mac's runner and reports pass or fail.

**Independent Test**: With the runner running, push to `main`; one `verify` run appears on the runner and passes (quickstart D3).

- [X] T004 [US1] Create .github/workflows/verify.yml exactly as specs/018-ci-verify-workflow/contracts/verify-workflow.md: `name: verify`; triggers push to `main` and pull_request against `main`; `permissions: contents: read`; the concurrency block of research R4; job `verify` with `runs-on: [self-hosted, macOS, xcode-27]`, `timeout-minutes: 30`, steps `actions/checkout@v7` with `persist-credentials: false` and `run: ./Scripts/verify.sh` (FR-002–FR-007a)
- [X] T005 [US1] Run quickstart L2: `actionlint .github/workflows/verify.yml` exits 0 with no output, and the file matches the contract step for step (SC-005); declare the custom `xcode-27` label in .github/actionlint.yaml so actionlint accepts it
- [ ] T006 [US1] **DEVELOPER** Quickstart D3: after US2's pull request is green, merge it; confirm the push to `main` starts exactly one `verify` run on the runner, it passes, and it finishes within the 30-minute limit (SC-001, SC-002); record the run URL and duration in specs/018-ci-verify-workflow/quickstart.md

**Checkpoint**: Pushes to `main` are verified.

---

## Phase 4: User Story 2 - A pull request is verified before merge (Priority: P2)

**Goal**: The same job runs on every pull request against `main` and shows its result there.

**Independent Test**: Open a pull request; `verify / verify` runs and shows its result (quickstart D2).

- [ ] T007 [US2] **DEVELOPER** Quickstart D2: push branch `018-ci-verify-workflow` and open its pull request against `main` as Yoi-Nami-Ra; confirm one `verify / verify` check runs on the runner, its log shows checkout then the script's sections ending `VERIFICATION PASSED`, and the pull request shows it passed (SC-003); record the run URL in specs/018-ci-verify-workflow/quickstart.md

**Checkpoint**: Pull requests are verified; the merge rule can be applied.

---

## Phase 5: User Story 3 - A broken change turns the job red (Priority: P3)

**Goal**: Evidence that the job really fails when a check fails, without the broken commit ever reaching `main`.

**Independent Test**: A throwaway pull request with a failing test fails `verify / verify` and is closed unmerged (quickstart D4).

- [ ] T008 [US3] **DEVELOPER** Quickstart D4: on branch `throwaway/ci-red-check`, add Tests/SwiftSkySimulationTests/CIMustFail.swift with a failing test, push, open a pull request; confirm `verify / verify` fails with `FAIL swift test` naming `ciMustFail` (SC-004); keep the pull request open for T009
- [ ] T009 [US3] **DEVELOPER** Quickstart D5 on the same throwaway pull request: push two empty commits about ten seconds apart; confirm the first one's run ends cancelled and the second runs (FR-007a, SC-001a)
- [ ] T010 [US3] **DEVELOPER** Close the throwaway pull request unmerged and delete its branch remotely and locally (`gh pr close --delete-branch`, `git branch -D throwaway/ci-red-check`); confirm `main` never contained the commit (FR-013); record both run URLs in specs/018-ci-verify-workflow/quickstart.md

**Checkpoint**: The job is proven able to fail.

---

## Phase 6: User Story 4 - The developer can start and stop the runner (Priority: P3)

**Goal**: The written steps are enough to operate the runner.

**Independent Test**: Stop, see Offline, start, see Idle, following only .github/RUNNER.md (quickstart D6).

- [ ] T011 [US4] **DEVELOPER** Quickstart D6: following only .github/RUNNER.md, stop the runner and see it Offline with a new run Queued; start it and see it Idle and the queued run start (SC-006); fix .github/RUNNER.md if any step was missing

**Checkpoint**: The runner can be operated from the repository's own notes.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Retire the records of the gap and prove nothing regressed.

- [ ] T012 [P] Update the header comment of Scripts/verify.sh (comments only, research R10): it is the CI job body of .github/workflows/verify.yml rather than a future one; then run quickstart L3 (`git diff main -- Scripts/verify.sh` shows only `#` lines; `time ./Scripts/verify.sh` ends `VERIFICATION PASSED`) and record the time in specs/018-ci-verify-workflow/quickstart.md (FR-005, SC-008)
- [ ] T013 [P] In specs/001-metal-app-shell/plan.md remove the "No CI pipeline" row from Complexity Tracking and the CI-absence clause of the note above the table, and rewrite the Principle II rows in the Constitution Check tables to cite the CI job (.github/workflows/verify.yml, spec 018) (FR-010)
- [ ] T014 [P] In CLAUDE.md: add 018 to "Built so far"; replace "and wired into CI once a remote exists" with the CI as it now is; add a Key-locations entry for .github/workflows/verify.yml and .github/RUNNER.md naming the self-hosted runner, its labels, the merge rule (FR-014) and that pushing, runner and GitHub settings are the developer's (FR-011)
- [ ] T015 Run quickstart L4 (`grep -n -i "no remote\|no CI\|CI absence\|CI-absence\|once a remote" specs/001-metal-app-shell/plan.md CLAUDE.md`) and confirm no line says there is no remote or no CI (SC-007)
- [ ] T016 Run ./Scripts/verify.sh on the finished branch and confirm `VERIFICATION PASSED` (SC-008)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: none.
- **Foundational (T002, T003)**: T002 first; T003 (developer) needs T002.
- **US1 (T004–T006)**: T004, T005 need nothing but Setup. T006 needs T003 (runner online) and T007 (the pull request to merge).
- **US2 (T007)**: needs T003, T004 and Polish T012–T016 committed (the pull request carries the whole feature).
- **US3 (T008–T010)**: needs T006 (the workflow on `main`); T009 needs T008; T010 needs T009.
- **US4 (T011)**: needs T003; best after T010 so it does not interrupt a run.
- **Polish (T012–T016)**: T012–T014 need T002 and T004 (they name those files); T015 needs T013, T014; T016 last of the agent tasks.

### Agent work vs developer work

Agent-doable: T001, T002, T004, T005, T012–T016. Developer-only: T003, T006–T011. The agent's part ends
with T016 and a committed branch; the developer then runs T003, T007, T006, T008–T011 in that order.

### Parallel Opportunities

- T012, T013, T014 touch different files and can be done in parallel.
- T004 and T002 touch different files and can be done in parallel.

---

## Parallel Example: Polish

```text
Task: "T012 Update the header comment of Scripts/verify.sh"
Task: "T013 Retire the CI-absence record in specs/001-metal-app-shell/plan.md"
Task: "T014 Update CLAUDE.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. T001, T002, T004, T005: the workflow and the runner notes exist and lint clean.
2. Developer: T003 (runner), T007 (pull request), T006 (merge; `main` verified). That is US1 delivered.

### Incremental Delivery

1. US1 + US2 arrive together, because the feature branch reaches `main` through its own pull request.
2. US3: the red check on a throwaway pull request.
3. US4: the start/stop walk-through.

---

## Notes

- **DEVELOPER** tasks stay unchecked until the developer has done them; the agent never pushes, opens
  pull requests, registers or starts the runner, installs a LaunchAgent, or changes GitHub state.
- Commit after each phase of agent work.
- `.tickets/9.yaml` moves to done only after the developer checks pass (the ticket's "Done when").
