# Specification Quality Checklist: Metal App Shell

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-26
**Last validated**: 2026-07-26 (after a sixth `/speckit-clarify` pass; 20 questions answered in total —
the sixth pass asked none, confirming saturation)
**Feature**: [spec.md](../spec.md)

## Content Quality

- [ ] No implementation details (languages, frameworks, APIs) — see Note 1
- [x] Focused on user value and business needs
- [ ] Written for non-technical stakeholders — see Note 2
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [ ] Success criteria are technology-agnostic (no implementation details) — see Note 1
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [ ] No implementation details leak into specification — see Note 1

## Notes

**Note 1 — three items now fail on technology naming. Accepted, but the earlier rationale no longer
holds and was not quietly stretched to keep the checkmarks.**

Through the second clarification pass these items passed on a specific ground: technology names were
confined to the **Input** line (a verbatim quote of the user's description), the **Assumptions**
section (SwiftUI/UIKit/AppKit, because the user's instruction was explicitly conditional on them), and
the **Dependencies** section (the toolchain, a genuine dependency) — while the Functional Requirements
and Success Criteria stayed behavioural: "the 2D rendering pipeline", "the platform-UI layer", "the
logic layer".

The third pass broke that. Requirements and criteria now name platform technologies directly:

- **FR-016a / SC-018** name Mac Catalyst and "Designed for iPad". There is no vendor-neutral way to
  require that specific destinations be disabled — the requirement *is* about those named features.
- **SC-015** names strict concurrency checking and thread/address sanitisers. These are verification
  tooling rather than product implementation, but they are unambiguously toolchain-specific.
- **FR-002c** names sRGB and an 8-bit-per-channel format, and **SC-019** names a frame capture. Added in
  the fourth pass; same character as the above, and they do not change these items' already-failed state.

So the three items are marked failed against the criterion as literally worded. **All three are
accepted as-is and none blocks planning.** The alternative — restating them as "the second Mac
variant" and "the compiler's data-race checking" — would obscure exactly which switches must be
thrown, trading a real, actionable requirement for a passing checkbox. The constitution (v1.0.0,
*Technology & Platform Standards*) already ratifies Swift + Metal + SwiftUI, so naming the platform is
not smuggling in an unmade decision.

**Note 2 — the one item that does not pass, and won't.** FR-010–FR-015 (layer boundaries), FR-020
(no per-frame heap allocation), FR-021a–FR-021f (fixed timestep, accumulator clamp, instrumentation),
FR-026 (diagnostics), SC-004/SC-004a (allocation measurement, release-build absence) and SC-013
(deterministic tick sequences) are engineering-facing and cannot be made otherwise: this feature's
deliverable *is* an architecture and a build. The second clarification pass made this *more*
pronounced, not less, which was the right trade — those decisions are expensive to retrofit. They are
at least stated as observable, verifiable outcomes — a violating build fails, the logic layer tests
with no GPU, identical tick sequences produce identical state — so a non-technical reviewer can still
judge whether they were met. The three user stories and the remaining Success Criteria are readable
without engineering context. **Accepted as-is; not an outstanding action item.** Later,
content-bearing features should pass this item cleanly, and it should be re-checked strictly for them.

**Note 3 — resolved clarifications (Session 2026-07-26).** All ten are recorded in the spec's
`## Clarifications` section. First pass:

1. Minimum platform versions → iOS 26 / macOS 26; baseline device = oldest each supports (FR-022,
   FR-023). This unblocked SC-001, SC-003, and SC-005, which all measure against that baseline.
2. Frame loop → continuous, display-paced while visible (FR-021). Makes SC-003 a real gate rather
   than a vacuous one.
3. Renderer-failure surfacing → minimal platform-UI notice, then terminate (FR-024–FR-027). This
   resolved a genuine self-contradiction: the old Edge Cases text promised the user a message while
   FR-007 forbade any visible platform-UI content. FR-007 and SC-002 were amended to carve out the
   exception explicitly.
4. iOS orientations → landscape-left and landscape-right only (FR-006b). Made User Story 2's
   rotation scenario testable, and added the iPad-multitasking edge case it implies.
5. Idle memory budget → measure and record the baseline, plus a loose absolute ceiling as a bloat
   tripwire (SC-005). The ceiling's number is deferred to the plan by design.

Second pass:

6. Simulation timestep → fixed, with a clamped accumulator, decoupled from render rate (FR-021a–c,
   SC-013). Corrected an implicit variable-timestep commitment the spec had made via the Frame Tick
   entity; added the Time Accumulator entity and the long-stall edge case.
7. CI scope → no pipeline; a checked-in verification script CI can call verbatim (FR-019a, SC-008a).
   The constitution's CI clause is now an explicitly recorded deferral with "no remote configured" as
   the reason, rather than an unaddressed omission.
8. Layer-boundary verification → one-time manual proof per direction, evidence in the quickstart
   (SC-009, User Story 3 independent test). Removed an unmeetable standing gate: a permanently failing
   build cannot be committed.
9. Performance measurement → debug/profiling-build-only instrumentation, log-only (FR-021d–f,
   SC-004a). Gives Principle III's recurring before/after obligation a repeatable mechanism instead of
   a manual profiler session per feature.
10. macOS window sizing → 1280×720 default, 640×360 minimum, aspect free (FR-006a). Made User
    Story 1's "resize to its minimum" scenario testable.

Two contradictions were also fixed without spending a question, because the answers were forced:
User Story 2's narrative still implied free rotation after the landscape-only decision, and FR-001's
ban on launch placeholders collided with the OS-mandated pre-first-frame appearance (now FR-004a,
required to be black and empty).

**Note 4 — deferred to `/speckit-plan`, not gaps in the spec.** Genuinely plan-level: module topology
(whether the layer modules are local packages or Xcode targets) for FR-013's build-time enforcement;
the specific baseline device models named by FR-023; and the tripwire ceiling number in SC-005.
Resolved since this note was first written: observability (now FR-021d–f) and the tick rate and clamp
constants (now 60 Hz and 4 ticks, FR-021a–b).

**Note 5 — third pass (clarifications 11–15).** This pass was worth running despite the previous
report recommending against it. Two of the five findings were things the *platform* decides when the
spec is silent, which is the worst kind of gap:

11. Window multiplicity → exactly one, multi-window explicitly disabled (FR-006c, SC-014). The default
    scene configuration grants ⌘N and a Window menu for free; the app would have accepted a second
    window with undefined behaviour against a single Simulation State.
12. Concurrency model → dedicated off-main isolation domain (FR-028–FR-033, SC-015–SC-017). **Chosen
    against the recommendation**, which was main-actor-everything. This is the most consequential
    decision in the spec and adds a marshalling boundary, transfer-safety obligations, and explicit
    drain-on-teardown ordering. Recorded in Assumptions as requiring a Complexity Tracking entry in
    the plan under Principle V — the plan must not present it as the obvious default.
13. Window close → quits the app (FR-006d). Fixed a dead end created by clarification 11: one window,
    no way to open another, so closing it would have left a running process with no reachable UI.
14. Tick rate → 60 Hz, catch-up clamp 4 ticks (FR-021a–b, SC-013). Removed the last undocumented
    constants.
15. Mac build path → native macOS target only, Mac Catalyst and "Designed for iPad" disabled
    (FR-016a, SC-018). Prevented a second Mac variant with iPad window and orientation behaviour.

The concurrency choice is also why three checklist items regressed — see Note 1.

**Note 6 — fourth pass (clarifications 16–19).** Stopped at four questions rather than padding to five;
the two remaining gaps (localisation, icon/branding scope) had obvious defaults and are recorded in
Assumptions instead. Two of the four findings were **latent inconsistencies**, where the spec's stated
purpose and its literal requirements had drifted apart:

16. Draw call → a full-screen black quad through compiled shaders and a real pipeline state, not a
    clear-only pass (FR-002a–b, SC-019). FR-001 as written was satisfiable by a clear pass that exercised
    no shader, no pipeline state, and no draw call — which would have left the pipeline this feature
    exists to prove entirely unexercised, and made FR-024/FR-026's named shader and pipeline-state
    failure modes unreachable dead requirements.
17. Surface format → sRGB, opaque, 8-bit, black defined as (0,0,0) at full alpha (FR-002c). FR-002 said
    "black" without ever defining it.
18. Logic→render hand-off → carries the accumulated tick count every frame (FR-012a–b, SC-020). Same
    shape of gap as 16: FR-012's interface could have compiled and shipped carrying nothing, leaving both
    the seam and its cross-domain transfer (FR-030) unproven. **Chosen over the more vivid option** of
    driving the quad's colour from Simulation State, because colour is a presentation concern and putting
    it in the logic layer would have undercut FR-010 on the very feature that establishes it — so
    FR-012b now forbids that explicitly.
19. Drawable acquisition failure → skip the frame, retain accumulated time, never fatal, never
    user-visible (FR-027a–b, SC-021). FR-024–FR-027 covered initialisation failure only; the per-frame
    transient case was unaddressed, and treating it as fatal would have killed the app during ordinary
    window dragging — the exact scenario SC-006 and SC-016 stress-test.

A Low Power Mode / thermal edge case was also added without spending a question: FR-020's
display-rate-following pacing already handles it, and FR-021 forbids adding throttling on top.

**Note 7 — fifth pass: one decision, four repairs. This is what convergence looks like.** Only one
question was worth asking; the rest of the pass fixed inconsistencies that *earlier passes had
introduced*, which is the signature of a spec that has stopped gaining and started churning.

20. Simulation shape → plain value types advanced by a pure function; the logic layer contains no
    concurrency constructs at all, and isolation belongs to the loop that holds them (FR-012c–d).
    Key Entities previously said these types "live inside the frame loop's isolation domain" without
    saying whether the isolation belonged to the types or the loop — which decided whether every
    simulation test would be sync or async.

Repairs, none of which needed a decision:

- **SC-021 contradicted FR-021b.** It claimed no simulation time is lost across skipped frames, but the
  catch-up clamp discards anything beyond 4 ticks. Now scoped to skip runs within the clamp, with the
  falling-behind behaviour stated as documented rather than defective.
- **"Dropped" and "skipped" frames were used as if interchangeable.** SC-003 forbade dropped frames while
  FR-027a mandated skipping them under backpressure. FR-027c now defines both terms distinctly and
  requires the instrumentation to report them separately.
- **SC-006 and SC-016 were near-duplicate resize stress tests.** Differentiated: SC-006 covers visual
  correctness across the size and orientation range, SC-016 covers concurrency behaviour under sanitiser.
- **User Story 1's narrative listed closing as an ordinary window behaviour**, reading as a contradiction
  of FR-006d's close-to-quit. Now stated explicitly in the narrative.
- **FR-028's "quality of service appropriate to real-time work"** was an unquantified adjective; it now
  defers the specific class to the plan, matching how FR-023 and SC-005 handle their deferred numbers.

**Assessment: the spec is saturated.** Four consecutive passes moved it from 10/16 to 12/16 with the four
remaining failures all explicitly accepted; this pass moved nothing. Further clarification should happen
after `/speckit-plan` surfaces real design constraints, not before.

**Note 8 — sixth pass: no questions asked.** A full taxonomy scan produced no candidate question above
the materiality bar. The only change was a wording correction in the Key Entities preamble, which had
credited FR-012c with establishing all four entities as value types when it names only two. Every
taxonomy category is Clear or explicitly Outstanding-by-choice. This is the confirmation the fifth pass
predicted: the spec is done, and remaining decisions belong to `/speckit-plan`.
