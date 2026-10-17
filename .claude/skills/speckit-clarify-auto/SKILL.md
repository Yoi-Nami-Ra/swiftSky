---
name: speckit-clarify-auto
description: "Hybrid variant of speckit-clarify: resolves spec ambiguities the evidence already answers (code, constitution, ticket, earlier specs) on its own, marked as assumptions, and asks the user only the questions that turn on product intent, scope, priority or compliance, batched into one prompt. Use instead of /speckit-clarify to cut round-trips while keeping the user on the real decisions."
argument-hint: "Optional focus areas, ticket id, or extra context (e.g. 'PROJ-123, focus on error states')"
compatibility: "Requires a Spec Kit project (.specify/ directory) with the speckit-clarify skill or command installed for Claude"
model: opus
effort: high
metadata:
  scope: project
  base: speckit-clarify
user-invocable: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## How this skill relates to speckit-clarify

Locate the base clarify instructions, first match wins:

1. `.claude/skills/speckit-clarify/SKILL.md`
2. `.claude/commands/speckit.clarify.md`

Read the base and execute it **exactly as written** (Pre-Execution Checks, every
Outline step except "Sequential questioning loop", behavior rules, Mandatory
Post-Execution Hooks, Completion Report), with only the overrides below. Re-reading the
base on every run keeps this variant correct after `specify` upgrades rewrite it. Base
steps are named by their heading text, never by number: upgrades renumber them. If a
step named below no longer exists in the base, stop and tell the user this wrapper
needs updating for their Spec Kit version; do not guess its replacement.

If no base file is found, stop and tell the user to restore it
(`specify init --here --integration claude`); do not improvise the clarify flow.

## Override A — gather evidence before triage (runs after the base's "structured ambiguity & coverage scan")

Besides the constitution and spec the base already loads, read only what the candidate
questions need:

- the ticket, if `$ARGUMENTS` or the spec names one, from wherever this project tracks
  work: an issue-tracker MCP that is connected (Linear, Jira, GitHub issues via `gh`),
  or a repo-local backlog (e.g. `.tickets/`, `docs/tickets/`). Skip silently if none is
  reachable;
- `CLAUDE.md` / `AGENTS.md` and any project skills (`.claude/skills/`, other than
  `speckit-*`) whose scope matches the question;
- existing code for the feature area (search, then read excerpts — not whole trees);
- up to 3 earlier specs under `specs/` touching the same area, for precedent.

Stop gathering once each candidate question has an answer or is clearly unanswerable
from evidence. Do not run builds or tests.

## Override B — candidate queue (replaces the limit in the base's "prioritized queue of candidate clarification questions")

Build the prioritized queue exactly as that base step describes, but with a **maximum of
10 candidates** (auto-resolved ones are cheap). The cap on questions put to the user
stays **5**.

## Override C — triage instead of the sequential loop (replaces the base's "Sequential questioning loop")

Classify every candidate as **AUTO** or **ASK**:

**AUTO** — the answer follows from evidence, and a reasonable reviewer would not
dispute it:
- an existing code pattern, API contract, data model, or architectural rule decides it;
- the constitution, `CLAUDE.md`, or a project skill prescribes it;
- the ticket states it, or an earlier spec set a precedent the new feature should follow;
- it is an industry-standard default with no product trade-off (e.g. retry idempotent
  reads, show a loading state, localize user-visible strings when the project does).

**ASK** — anything that turns on someone's judgement rather than on evidence:
- product scope, what is in or out, feature priority;
- business rules, pricing, limits or amounts that are a product choice;
- legal, privacy, compliance, data retention;
- user-visible copy or UX behavior with no design and no precedent;
- evidence conflicts (code says one thing, ticket another);
- your confidence in the AUTO answer is below high.

When unsure, classify as ASK. Wording like "deliberate decision" or "if X isn't
required" in the ticket is not by itself a reason to ASK — trace the code first.

### AUTO handling

For each AUTO item: pick the answer, record it in working memory together with its
evidence (a `path:line`, a constitution article, a ticket id, or a spec number), and
integrate it via the base's "Integration after EACH accepted answer" — but write the
Clarifications bullet as:

`- Q: <question> → A: <answer> _(assumed — <evidence>)_`

### ASK handling

- If there are no ASK items, skip to integration.
- Otherwise put the top ≤5 ASK items (by Impact × Uncertainty) to the user **in one
  batch** with the `AskUserQuestion` tool (max 4 questions per call, so 5 items = one
  call of 4 + one call of 1). Each question:
  - is a full interrogative ending with `?` (the "Question writing quality" rules
    from the base's sequential questioning loop apply, if present);
  - has 2–4 options, the recommended one first with `(Recommended)` in the label and a
    one-sentence why in its description;
  - leaves free-form answers to the tool's built-in "Other" choice.
- If `AskUserQuestion` is unavailable (non-interactive run), fall back to the base's
  "Sequential questioning loop" for the ASK items.
- ASK items beyond 5 go to the Completion Report under **Deferred**.
- Integrate the user's answers via the base's "Integration after EACH accepted answer"
  with the normal bullet format `- Q: <question> → A: <answer>` (no "assumed" marker —
  the user decided).

An answer of "recommended"/"yes" from the user, or picking the `(Recommended)` option,
counts as a user decision, not an assumption.

## Override D — completion report additions

Add to the base Completion Report, before the coverage table:

```
Auto-resolved: <n>   Asked: <m>   Deferred: <k>

| # | Question | Answer | Evidence |
|---|----------|--------|----------|
| 1 | ...      | ...    | path:line / ticket / constitution §X |
```

End with one line: `Review the "assumed" bullets in spec.md → ## Clarifications; to
overturn one, re-run /speckit-clarify-auto "<item>: <your answer>"`.

When `$ARGUMENTS` contains an override of that shape (`<item>: <answer>`), apply it
first: replace the matching assumed bullet and its integrated text with the user's
answer (dropping the "assumed" marker), then continue with any remaining ambiguities.

## Done When

- [ ] Every candidate classified AUTO or ASK, with evidence recorded for each AUTO
- [ ] ASK items put to the user in one batch (≤5), or none needed
- [ ] All answers integrated per the base's integration step; assumed ones carry the `_(assumed — …)_` marker
- [ ] Base validation, write-back, checklist re-validation, hooks and Completion Report done, plus the Override D table
