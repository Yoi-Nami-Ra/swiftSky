# Feature Specification: CI Running the Verification Script

**Feature Branch**: `018-ci-verify-workflow`

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "SKY-9 — Add git remote and CI running verify.sh" (`.tickets/9.yaml`).
Constitution v1.1.0 Principle II requires CI once the repository has a remote; until then
`Scripts/verify.sh` is the required stand-in (specs/001-metal-app-shell FR-019a), and its absence is
recorded in 001's Complexity Tracking. The ticket asks for: the GitHub account confirmed and `gh` logged
in to it; a private repository named swiftSky with `main` pushed as `origin`; a self-hosted GitHub Actions
runner on this Mac, registered to that repository only, labelled `self-hosted`, `macOS`, `xcode-27`,
using this Mac's Xcode 27.0, with start and stop documented; a workflow that, on push to `main` and on
pull requests, checks out the repository on that runner and runs `./Scripts/verify.sh` exactly as it is,
with no other steps; and the records of the gap updated (001's plan and CLAUDE.md; specs 002–015 stay as
merged history). Out of scope: a GitHub-hosted runner, launching the iOS app on a simulator in CI, and
branch protection rules. Done when the remote exists and `main` is pushed; a push to `main` and a pull
request each trigger the workflow, which runs on this Mac and passes; a deliberately broken commit makes
the job fail and is then reverted; and the 001 plan and CLAUDE.md no longer say there is no remote or CI.

**Already done before this spec**: the private repository `Yoi-Nami-Ra/swiftSky` exists, it is `origin`
(reached through the `yoinamira-github` ssh host alias, see CLAUDE.md), and `main` is pushed with its full
history. The ticket's scope items 1 and 2 therefore need no work here, beyond recording that they hold.

## Overview

Every change to swiftSky is checked today by one person running `./Scripts/verify.sh` by hand. The
script was written to become a CI job body unchanged. This feature makes the repository host run it:
every push to `main` and every pull request gets a pass or fail result, produced on this Mac, with the
same Xcode the developer uses, and visible on the commit and the pull request.

The runner is a self-hosted one on this Mac, not a hosted machine: this Mac already has the exact
toolchain the script needs (Xcode 27.0 with the Metal toolchain), and it costs no build minutes. The
price is that CI runs only while this Mac is on and the runner is running; a push made while it is off
waits in the queue.

Out of scope: a hosted runner, running the app on a simulator or device, branch protection rules, any
change to what `verify.sh` checks, caching, build artefacts, and notifications beyond what the host
shows by default.

### Relationship to earlier specs

- **001 FR-019a** defined `Scripts/verify.sh` as the single checked-in verification command and the
  future CI job body. This feature makes it that job body and changes nothing in it.
- **001 plan.md** records "No CI pipeline" in Complexity Tracking and in its Principle II rows. This
  feature removes that record, because the condition it describes ends.
- **Specs 002–015** cite the CI absence in their own plans. They are merged history and stay as they
  are; plans from this one on cite the CI job instead.

## Clarifications

### Session 2026-10-07

- Q: What time limit should a verification job have? → A: 30 minutes. A local run on this Mac takes a few
  minutes; 30 leaves room for a cold build and a busy machine while making sure a hung job frees the only
  runner well before the host's 6-hour default.
- Q: When a newer commit arrives while an older job for the same branch or pull request is still running,
  what happens to the older one? → A: On pull requests the older run is cancelled; on `main` every pushed
  commit runs to completion, so each commit on `main` keeps its own result. (Pushes to other branches do
  not start runs of their own; they are verified through their pull request.)
- Q: How does the runner run on this Mac? → A: As a background service under the developer's own user,
  installed with the runner's own service script, so it starts at login and keeps running without a
  terminal window; starting it by hand in a terminal is documented as the fallback.
- Q: Where does the runner's documentation live? → A: In a standing file next to the workflow,
  `.github/RUNNER.md`, which CLAUDE.md points to; this spec's quickstart holds the one-time setup and the
  acceptance checks, and links to it.
- Q: Without branch protection (out of scope), how is Principle II's "CI MUST gate merges" met? → A: By
  rule, not by setting: a pull request is not merged unless its verification job passed for its head.
  The rule is written in `.github/RUNNER.md` and CLAUDE.md, and the plan's Complexity Tracking records
  that the gate is procedural rather than enforced, with branch protection named as the enforced
  alternative left out by the ticket.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A push to main is verified automatically (Priority: P1)

The developer pushes commits to `main`. Without doing anything else, the repository host starts the
verification job on this Mac's runner, the job runs the verification script, and the commit shows a
pass or a fail.

**Why this priority**: This is the CI that Principle II requires once a remote exists. Without it the
feature delivers nothing.

**Independent Test**: With the runner running, push a commit to `main` and watch the commit's checks:
one verification job appears, runs on this Mac's runner, and ends green.

**Acceptance Scenarios**:

1. **Given** the runner is running and `main` is green locally, **When** the developer pushes to `main`,
   **Then** exactly one verification job runs on this Mac's runner and passes.
2. **Given** the job runs, **When** its log is opened, **Then** it shows the checkout and the
   verification script's own output, stage by stage, and nothing else runs.
3. **Given** the runner is stopped, **When** the developer pushes to `main`, **Then** the job waits in
   the queue and runs once the runner starts again (within 24 hours); it does not fail for lack of a
   runner.

---

### User Story 2 - A pull request is verified before merge (Priority: P2)

The developer opens a pull request (from a feature branch, as every spec branch is). The same job runs
against the pull request and its result shows on the pull request, so a red change is visible before it
reaches `main`.

**Why this priority**: Principle II asks CI to gate merges. A visible result on the pull request is what
makes that gate possible; P1 alone only reports after the fact.

**Independent Test**: Open a pull request from a branch; the verification job runs and its result shows
on the pull request page.

**Acceptance Scenarios**:

1. **Given** a branch with a passing change, **When** a pull request is opened against `main`, **Then**
   the verification job runs and the pull request shows it passed.
2. **Given** an open pull request, **When** a new commit is pushed to its branch, **Then** the job runs
   again for the new head.

---

### User Story 3 - A broken change turns the job red (Priority: P3)

A change that breaks the build or a test makes the job fail, and the failing stage can be read in the
job's log.

**Why this priority**: A job that cannot fail proves nothing. This story is the evidence that the job
really runs the checks, and it is demonstrated once, on a throwaway pull request.

**Independent Test**: On a throwaway branch, add a test that fails, open a pull request, and see the job
fail on the `swift test` stage; then close the pull request and delete the branch.

**Acceptance Scenarios**:

1. **Given** a throwaway pull request whose only change is a deliberately failing test, **When** the job
   runs, **Then** it fails, and its log names the failing stage.
2. **Given** that demonstration is done, **When** the pull request is closed without merging and its
   branch deleted, **Then** `main` never contained the broken commit.

---

### User Story 4 - The developer can start and stop the runner (Priority: P3)

The developer can read, in the repository, how the runner was installed, how to start and stop it, how to
check it is online, and what happens to jobs while it is off.

**Why this priority**: The runner is a service on a personal machine. Without written steps, it gets
forgotten or left in an unknown state, and CI silently stops.

**Independent Test**: Following only the written steps, stop the runner, confirm it shows offline, start
it, and confirm it shows online again.

**Acceptance Scenarios**:

1. **Given** the written steps, **When** the developer follows them, **Then** the runner can be started,
   stopped and checked without looking anything up elsewhere.

### Edge Cases

- **This Mac is off or asleep, or the runner is stopped**: the job queues and runs later. The host may
  cancel a job that has waited too long (it does so after 24 hours); the steps say to re-run it.
- **Two pushes in quick succession**: there is one runner, so jobs run one after another. On a pull
  request, a newer push cancels the older, still-running job for the same pull request; on `main`, every
  commit's job runs to completion.
- **The Mac's Xcode changes** (an update, or a different selected Xcode): the job runs whatever Xcode is
  selected on the Mac. The `xcode-27` label is a promise the developer keeps; the steps say to change the
  label and the workflow together when Xcode changes.
- **The developer builds locally while a job runs**: both share the machine's CPU and Xcode's derived
  data folder; the job may take longer. Neither must break the other's result.
- **The Metal toolchain is missing on the Mac**: `verify.sh`'s own preflight fails the job with its own
  message; nothing extra is added.
- **A job hangs**: it is stopped and marked failed after 30 minutes, which frees the runner.
- **Pull requests from forks**: the repository is private, so no outside fork can run code on this Mac.
  This is the reason a self-hosted runner is acceptable here; it must not be reused for a public
  repository.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST have the private GitHub repository `Yoi-Nami-Ra/swiftSky` as `origin`,
  with `main` pushed. (Already true; this requirement records it and is checked, not built.)
- **FR-002**: The repository MUST contain one workflow that runs on every push to `main` and on every
  pull request against `main`.
- **FR-003**: The workflow MUST run its job only on a self-hosted runner carrying the labels
  `self-hosted`, `macOS` and `xcode-27` (the runner also carries the automatic `ARM64` label, which the
  workflow does not require).
- **FR-004**: The job's steps MUST be exactly two: check out the commit under test, then run
  `./Scripts/verify.sh` with no arguments. The job passes if and only if the script exits 0.
- **FR-005**: `Scripts/verify.sh`'s behaviour MUST NOT change. (Its header comment, which speaks of CI as
  future, may be brought up to date.)
- **FR-006**: The workflow MUST grant the job no more repository access than reading its contents.
- **FR-007**: A job MUST be stopped and marked failed when it runs longer than 30 minutes.
- **FR-007a**: A newer run for the same pull request MUST cancel the older one still in progress; runs for pushes to `main` MUST NOT be cancelled by later pushes.
- **FR-008**: The repository MUST document the runner in `.github/RUNNER.md`: where it is installed on this Mac, how it was
  registered (to this repository only, with the FR-003 labels), how to start, stop and check it, that it
  runs only while this Mac is on, that queued jobs wait, that the labels and workflow change together
  when Xcode changes, and the merge rule (FR-014).
- **FR-008a**: The runner MUST run as a background service under the developer's own macOS user, started
  at login; running it by hand in a terminal MUST be documented as the fallback.
- **FR-009**: The runner MUST be registered to this repository only, not to an account or organisation.
- **FR-010**: The "No CI pipeline" entry MUST be removed from `specs/001-metal-app-shell/plan.md`'s
  Complexity Tracking, its note above the table, and its two Principle II rows MUST cite the CI job
  instead.
- **FR-011**: `CLAUDE.md` MUST stop describing CI as future and MUST name the workflow, the runner and
  where its instructions are.
- **FR-012**: The steps that act on GitHub or install a service on this Mac — registering the runner,
  installing and starting it, pushing the workflow, opening pull requests, the broken-change
  demonstration — MUST be done by the developer by hand, following written steps. No automated agent
  performs them.
- **FR-013**: The broken-change demonstration MUST happen on a throwaway pull request that is closed
  unmerged; `main` MUST never contain the deliberately broken commit.
- **FR-014**: A pull request MUST NOT be merged unless its verification job passed for its current head
  (not while it is red, cancelled, queued or missing). This is
  a written rule (branch protection is out of scope), stated in `.github/RUNNER.md` and CLAUDE.md.

### Key Entities

- **Verification workflow**: the checked-in definition of when the job runs (push to `main`, pull
  requests), where (the labelled self-hosted runner) and what it does (checkout, verify script).
- **Self-hosted runner**: the agent installed on this Mac, registered to this repository, carrying the
  FR-003 labels, running jobs as the developer's own user with the Mac's own Xcode.
- **Verification job result**: pass or fail on a commit or pull request, with the script's log.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `git remote -v` shows the private repository and `origin/main` equals local `main` after
  the feature's commits are pushed.
- **SC-001a**: A second push to a pull request's branch cancels the first push's job if it is still
  running. The 30-minute job limit is checked in the workflow file rather than by letting a job hang for
  30 minutes on the only runner.
- **SC-002**: A push to `main` produces exactly one verification job, which runs on this Mac's runner and
  passes within the 30-minute limit; its duration is recorded next to a local `./Scripts/verify.sh` run's
  on the same Mac, for comparison.
- **SC-003**: Opening a pull request produces a verification job whose result shows on the pull request.
- **SC-004**: A throwaway pull request with a deliberately failing test produces a failed job whose log
  names the failing stage; the pull request is closed unmerged and `main` never contains that commit.
- **SC-005**: The workflow file contains no step other than checkout and the verification script.
- **SC-006**: Following only the written runner steps, the developer can stop the runner, see it
  offline, start it, and see it online again.
- **SC-007**: `specs/001-metal-app-shell/plan.md` and `CLAUDE.md` contain no statement that the
  repository has no remote or no CI.
- **SC-008**: `./Scripts/verify.sh` passes locally on the feature branch, unchanged in behaviour.

## Assumptions

- The repository host is GitHub and the CI system is GitHub Actions, as the ticket names.
- The runner runs as the developer's own macOS user, so it sees the same Xcode, Metal toolchain and
  command-line tools as a local run; nothing extra is installed for it.
- Xcode 27.0 (27A266a) is the selected Xcode on this Mac.
- The repository stays private. A self-hosted runner on a public repository would let anyone's pull
  request run code on this Mac, and is not acceptable.
- Branch protection is out of scope (ticket). "CI gates merges" (Principle II) is met by the written rule
  of FR-014 and the result shown on every pull request; the plan records that this gate is procedural.
- The agent preparing this feature writes files and runs local checks only. Everything that changes
  GitHub's state or installs a service is a written step for the developer (FR-012).
