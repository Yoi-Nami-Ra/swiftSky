---
name: speckit-implement-phased
description: "Orchestrates /speckit-implement one tasks.md phase at a time, each phase in its own fresh subagent (Sonnet), strictly sequentially: verifies every phase, commits it, and carries hand-off notes forward. Use instead of /speckit-implement for features with several phases, to keep the main context small and every phase reviewable."
argument-hint: "Optional: phase range ('phases 2-4'), ticket id, 'gates: <command>', 'commit: <template>', extra rules for every phase"
compatibility: "Requires a Spec Kit project (.specify/ directory, tasks.md) with the speckit-implement skill or command installed for Claude, and git"
metadata:
  scope: project
  base: speckit-implement
user-invocable: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

You are the **orchestrator**. Do not implement any task yourself; every code change is
made by a phase subagent. `SPEC_ROOT` is the directory that contains `.specify/` (it may
be a subdirectory of the git repository); run every command from there.

## Setup (once)

1. Read `SPEC_ROOT/.specify/feature.json` → `FEATURE_DIR`. Read `FEATURE_DIR/tasks.md`
   and list its phases (`## Phase N: …`) with their unchecked task ids. Skip phases with
   no unchecked tasks. If `$ARGUMENTS` names a phase range, keep only those phases.
2. Locate the base implement instructions, first match wins:
   `.claude/skills/speckit-implement/SKILL.md` → invoke as the `speckit-implement` skill;
   `.claude/commands/speckit.implement.md` → the subagent reads and follows that file.
   If neither exists, stop and tell the user to restore it
   (`specify init --here --integration claude`).
3. Find the ticket id: `$ARGUMENTS`, else the spec's `Input`, else the branch name.
   If there is none, leave it out.
4. Resolve the **quality gate** — the command(s) that prove a phase is sound — first
   match wins:
   - `gates: <command>` in `$ARGUMENTS`;
   - a verification/check command documented in `CLAUDE.md`, `AGENTS.md` or the
     constitution (e.g. `./Scripts/verify.sh`, `make check`, `npm test`);
   - a project skill whose name or description says quality gates / verification —
     then the gate is "run the `<skill>` skill";
   - the project's obvious build + test + lint commands (`package.json` scripts,
     `Makefile`, `Package.swift`, `pubspec.yaml`, `pyproject.toml`, …).
   Note also the gate's cheapest static part (analyze/lint/typecheck), if it has one,
   for the orchestrator's own re-check in step 9.
5. Resolve the **commit message convention**, first match wins:
   - `commit: <template>` in `$ARGUMENTS`;
   - a convention stated in `CLAUDE.md`, `AGENTS.md` or `CONTRIBUTING.md`;
   - the shape of the last 15 non-merge subjects in `git log` (prefix style, where the
     ticket id goes);
   - fallback: `<ticket> <phase title>`.
   Any commit trailers the session requires (e.g. Co-Authored-By) still apply.
6. If `FEATURE_DIR/checklists/` has unchecked items, show them and ask the user whether
   to proceed. Phase subagents cannot ask the user, so this gate lives here, and the
   phase prompt carries the user's answer to it. On "no", stop.
7. Show the phase list (phase | title | unchecked task ids), the resolved gate, and an
   example commit subject, then wait for the user's "go". The user may correct the gate
   or the convention here.

## Per phase, in order

8. Spawn **one** Agent with `subagent_type: general-purpose`, `model: sonnet`,
   `run_in_background: false`, and this prompt with the placeholders filled in. Append
   any per-phase rules from `$ARGUMENTS` under Rules.

   ```text
   You are implementing ONE phase of a Spec Kit feature. Work from <SPEC_ROOT>.
   Feature dir: <FEATURE_DIR>. Phase: <N> — <phase title>. Tasks: <task ids>.
   Notes from the previous phase: <NOTES FOR NEXT PHASE, or "none">

   <Invoke the speckit-implement skill | Read <base command path> and follow it> with the
   argument "Phase <N> only: tasks <ids>. Stop at the end of this phase."

   Rules:
   - Do only the tasks in this phase. If one depends on unfinished work from another phase, stop and report it; do not work around it.
   - Mark each finished task [x] in tasks.md.
   - Do not execute extension hooks, optional or mandatory, and do not commit. The orchestrator runs the hooks and commits.
   - Follow CLAUDE.md / AGENTS.md and the constitution.
   - Before returning, run the quality gate: <gate>. Fix failures caused by your changes.
   - Checklist gate (the base's "Check checklists status" step): <"all checklists pass" | the user's answer from setup step 6, quoted>. Apply that answer at the gate instead of asking again.
   - Never ask questions. If blocked by a product decision, stop and report it.

   Return ONLY this, at most 25 lines:
   STATUS: done | blocked | failed
   TASKS DONE: <ids>
   TASKS NOT DONE: <ids + one-line reason each>
   FILES CHANGED: <paths>
   GATES: <each gate step> <ok/fail>, tests <n passed / n failed / not run + why>
   BLOCKERS / DECISIONS NEEDED: <none | list>
   NOTES FOR NEXT PHASE: <anything the next phase must know>
   ```

9. **Verify. Do not trust the report alone:**
   - `git status --short` and `git diff --stat` match FILES CHANGED. No stray files,
     and nothing about to be committed that the project keeps out of git (env files,
     keys, credentials, local config, build output).
   - Every task in TASKS DONE is `[x]` in `tasks.md`.
   - The report is clean: no gate in GATES is `fail`, tests show `0 failed`, and
     TASKS NOT DONE is empty. Failures the subagent calls "not caused by my change"
     still fail this check.
   - Re-run the gate's cheapest static part yourself (from setup step 4) and confirm it
     is clean. If the gate has no cheap part, the earlier phases are committed on the
     report alone: re-run the whole gate after the last phase, and if it fails, say that
     any phase may be the cause.
10. If STATUS is `done` and every check above passes, stage **only** this phase's files
    by path (never `git add .` / `git add -A`) plus `tasks.md`, and commit with the
    convention from setup step 5. Then go to the next phase.
11. If STATUS is `blocked` or `failed`, or verification fails: **stop**. Show the user the
    report and the failing output, and wait. Do not spawn the next phase, and do not try
    to fix it yourself unless the user asks.

## Finish

12a. The base's extension hooks run here, never in a phase: before phase 1 the
     orchestrator runs the base's `hooks.before_implement` step once, and after the last
     phase its `hooks.after_implement` step once, exactly as the base describes them.
     With no `.specify/extensions.yml`, both are no-ops; say so in the report.

12. When every phase is done, if the `speckit-converge` skill (or
    `.claude/commands/speckit.converge.md`) exists, run it. If it appends a Convergence
    phase, report that and offer to run this skill again for it. If it does not exist,
    skip this step and say so in the report.
13. Report:

    | Phase | Status | Tasks | Commit |
    |-------|--------|-------|--------|

    Then the converge result (or "converge not installed") and any BLOCKERS collected
    along the way.

## Done When

- [ ] Gate and commit convention resolved and confirmed with the user before phase 1
- [ ] Every selected phase ran in its own subagent, one after another
- [ ] Each completed phase verified and committed separately, staged by path
- [ ] Stopped and reported at the first blocked, failed or unverified phase
- [ ] Converge run (when installed) and summary table reported
