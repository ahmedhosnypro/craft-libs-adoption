---
name: visual-judge
description: >
  Judge, score, verify, or audit images and screenshots with a rigorous
  verdict protocol. Use whenever the user asks whether a render, screenshot,
  UI, or artwork PASSES, looks right, is ready to ship, or needs a visual
  verdict: render-vs-original or implementation-vs-design comparison verdicts
  (PASS/FAIL), rubric-scored quality inspections (0-10 axes, READY/NEEDS
  FIXES), visual launch gates, defect registers with ground-truth adjudication
  of vision-model claims, and multi-model differential image audits. Do NOT
  use for: generating or editing design-tool UI prototypes; writing Storybook
  story doctrine; running the slide-recreation pipeline itself (this
  skill supplies only its judging doctrine); distilling a skill's
  improvements from transcripts; driving an image editor; or plain
  multi-model image description/OCR with no judging or verdict ask.
version: 1.0.0
---

# visual-judge

Judge, score, verify, or audit images and screenshots under a rigorous
verdict protocol: comparison verdicts (PASS/FAIL), rubric-scored inspections
(0-10 axes, READY/NEEDS FIXES), and defect registers in which every
vision-model claim is adjudicated against objective measurement before it
counts. The skill is harness-generic: it needs only a vision-capable reader
that returns text, plus file storage; every fancier route is an optional
accelerator (references/vision-gateway.md).

## When to use / when NOT to use

Use when the ask is a VERDICT about visual state:

- Does this render, screenshot, UI, or artwork PASS against its original,
  design, or spec?
- Is it ready to ship — score it and list what blocks it.
- Which of two candidates is the faithful or better one?
- Audit this image: what is actually wrong with it, and what is right?
- Run a visual gate over a set of captures before a launch or a merge.

Do NOT use for: generating or editing design-tool UI prototypes; writing
Storybook story doctrine; running a slide-rebuild pipeline itself
(this skill supplies only its judging doctrine); distilling a skill's
improvements from transcripts; driving an image editor; or plain image
description or OCR with no judging or verdict ask.

## The core loop

One page. Details live in the references; each step names its file.

1. **Frame the ask.** Pick the judge mode (comparison judge vs scoring
   inspector — see below) and the deliverable: verdict, scored report, or
   defect register. Read the governing docs (spec, design references, prior
   outcome files) and scan the machine-local pattern store for prior
   lessons on this target class before any capture or call. A comparison
   target is a structure-only imagination aid; a missing target means the
   phase is skipped and the skip is recorded, never improvised
   (references/rubric-axes.md).
2. **Set point-of-enough budgets.** Verification depth is capped up front:
   rank the candidates or regions, verify the top-10 only, one measurement
   each; first-verified-wins — a claim verified once is done, a rejected
   one is noted and the next candidate taken; diminishing returns is an
   absolute stop rule — when new checks stop changing the verdict, stop
   verifying and write the deliverable. Unverified tail candidates stay in
   the report, labeled as unverified.
3. **Gate on implementation existence (Phase 0).** Before any pixels are
   scored, prove the target exists and is wired: the surfaces the ask
   names actually render, and the feature's own checks pass where it ships
   any. A failed gate stops the loop — report what is missing, never score
   stubs; polishing an unbuilt feature produces beautiful lies. Missing
   pieces inside a built target stay structure deltas
   (references/rubric-axes.md).
4. **Probe the vision route.** One cheap, short-wall call on an
   already-banked image before any expensive judge call. A probe hang gets
   one paced re-probe; a wedged route gates every call behind probes
   (references/judge-prompt-patterns.md).
5. **Capture, state-verified.** Settle, verify the right target, confirm
   state immediately before and after the shot, and pixel-check every PNG
   (dimensions + mean) before spending vision on it
   (references/capture-protocol.md).
6. **Run the objective pre-check gate.** Mechanical checks on every capture
   before any vision call. A gate FAIL is a HIGH finding: fix it and retake
   the capture — never score it as-is. Judges never re-litigate what the
   gate measures (references/capture-protocol.md).
7. **Measure.** Pixel measurement for rendered artifacts, DOM measurement
   for live UI. Pre-register expected numbers before the capture where
   possible; ground truth wins any disagreement
   (references/defect-register.md).
8. **Inspect / judge, isolated.** One image per inspector (the comparison
   judge's sequential two-image pair is the sole exception), frozen
   versioned template, VIEW/CAPTURE/FACTS context lines, text-only
   transcript banked to a file (references/judge-prompt-patterns.md,
   references/vision-gateway.md).
9. **Classify the read before reacting.** PASS / FAIL / NO-RESULT per the
   failed-read taxonomy. Garbage is counted, retried within budget, never
   accepted as evidence (references/verdict-law.md).
10. **Arbitrate findings vs measurement, claim by claim.** Vision proposes;
    pixels and DOM dispose. A disproven finding is DISMISSED, never "fixed"
    (references/defect-register.md).
11. **Fix wave.** Cluster findings by files, one fixer per disjoint set,
    canonical recipes, shared-primitive findings escalated. One fix-loop
    cycle per defect, then residuals are reported
    (references/defect-register.md).
12. **Re-verify.** Objective pre-checks first, then re-judge as attempt N+1;
    from round 2 on, the arbitration ledger rides in the context lines
    (references/defect-register.md).
13. **Close out.** Bank the evidence: transcripts, measurements, defect
    dispositions, append-only outcome rows, verdict bound to the
    deliverable's exact bytes (hash). Parked rows and pending debt are
    labeled honestly, never silently dropped. Multi-target runs close out
    at the set level, not per target (references/launch-gates.md).
14. **Evolve.** Append the run's lessons to the machine-local
    pattern-vocabulary store — deduped, in the store's entry format, per
    its sanctioned sources; a recurring, generalizing lesson is a
    promote-candidate under the store's promotion law. The run ends with
    a lesson report: either the appended entries or an explicit
    `no new lessons` line, so the review visibly happened even when
    nothing changed (references/judge-prompt-patterns.md).

## Golden rules

1. A verdict exists only as a banked transcript whose coherent body ends in
   an explicit verdict line; everything else is FAIL, NO-RESULT, or a retry
   (references/verdict-law.md).
2. Probe before you judge — never spend an expensive vision call on an
   unprobed route (references/judge-prompt-patterns.md).
3. Prompts describe CONTENTS: surface anatomy, exact text, by-design facts;
   generic prompts hallucinate (references/judge-prompt-patterns.md).
4. Score what EXISTS — missing features are structure deltas on their own
   line, never axis findings (references/rubric-axes.md).
5. Scripts measure, judges judge — judges never re-litigate what the
   objective pre-check gate already decided
   (references/capture-protocol.md).
6. Measurement outranks the judge: vision proposes, pixels and DOM dispose
   (references/defect-register.md).
7. One image per inspector; the orchestrator loads no image bytes and reads
   text-only transcripts (references/vision-gateway.md).
8. Judge templates are frozen, versioned artifacts; measured facts travel in
   editable context channels, never by editing the template
   (references/judge-prompt-patterns.md).
9. Park, never drop — retries are budgeted, then the row is banked as debt
   with an honest label (references/verdict-law.md).
10. Evidence banks to files: UTF-8 transcripts, one parseable verdict line,
    verdict bound to bytes by hash, append-only history
    (references/verdict-law.md).
11. Capture is not trust — state verified before and after every shot; exit
    code 0 proves nothing (references/capture-protocol.md).
12. Human preference chooses between candidates but never waives the gate;
    ambiguity routes to a sign-off note, never silently into the verdict
    (references/verdict-law.md).
13. A measurement FAIL is a claim, not evidence — verify the checker before
    charging defects: wrong units, wrong windows, or a broken predicate
    make correct surfaces look defective. Fix the checker, re-run, and
    only then charge the defect (references/evidence-discipline.md).
14. Instrument hygiene: police the measuring tool, not just the vision
    read — stale probes, neighbor-ink windows, checker unit bugs, and
    single-hex ink predicates manufacture false findings and false
    negatives alike (references/evidence-discipline.md).
15. Forward-looking translation risk is marked, never charged as a
    present-tense defect: copy that is correct in the captured locale but
    will break when other locales land carries an `[i18n-risk]` marker on
    its own line (references/defect-register.md).

## Judge modes

Two named modes share one verdict law; the mode is a prompt plus
output-contract choice, not a separate doctrine.

**Comparison judge** — for fidelity questions ("does it match the
original/design?"). Input: exactly two images read sequentially in the
order their CAPTURE labels declare — labels are authoritative and
adjudication is order-independent; there is no hard-coded design-first or
recreation-first order. Output: a body that
acknowledges the ground rules, lists discrepancies with severity and
confidence, and ends in one terminal verdict line
(`FINAL VERDICT: PASS|FAIL ...`). A PASS requires the implementation to win
AND the body to be coherent. This is the only sanctioned two-image call.

**Scoring inspector** — for quality questions ("is it good?"). Input: one
image. Output: fixed header, per-axis scores 0-10 with the mean, findings as
`[HIGH|MEDIUM|LOW] element — defect — concrete fix`, terminal verdict
`READY|NEEDS FIXES` (READY = mean ≥ 9.5)
(references/rubric-axes.md).

Both modes share the ground-rules prelude, content-anchored context lines,
the failed-read taxonomy, the objective pre-check gate, measurement
arbitration, retry budgets, and evidence banking. When a target image
exists AND quality is asked, run the inspector on the implementation and
record the comparison as a separate declared phase.

## Evidence law

- Verdicts bank to files at run time; stdout-only verdicts are not evidence.
- Transcripts are UTF-8 end-to-end; a degenerate response never overwrites a
  valid transcript.
- One machine-parseable terminal verdict line per transcript, in a fixed
  format; anything ambiguous becomes a NOTE/sign-off item addressed to the
  human, never silently folded into (or out of) the verdict.
- Every verdict is bound to the exact bytes judged: hash the deliverable
  (e.g. md5) before and after; a PASS for other bytes is void.
- Outcome files keep a fixed structure; score history is append-only; audits
  extend via additive addenda, never rewrites; nothing certified is
  deleted.
- Crash safety: outcome skeleton before field work; every transcript banked
  the moment it exists; a respawned worker reads banked state first;
  liveness is heartbeat/claim, and a quiet phase is not death — bare disk
  mtime is not liveness truth (references/vision-gateway.md).
- Single-model certificates are valid but must say so; verdicts carry
  leg-count labels; banned-route verdicts are void
  (references/vision-gateway.md).
- Runtime data — transcripts, verdicts, outcome files, pattern vocabulary,
  route notes — lives in a machine-local store outside any repo (convention:
  `~/.visual-judge/` or a per-run scratch directory) and is never committed;
  committed files reference it only as a whole.

## Vision access

Contract: input = image path(s) + a frozen prompt + context lines; output = a
UTF-8 text transcript banked to a file. The judge layer never needs to know
how the bytes reached a model.

Fallback ladder — every tier documented; tier 3 alone keeps the skill
functional on hosts with no subagent facility and no gateway:

- **Tier 1 (baseline):** an isolated harness subagent with vision — one
  image per call, returning text only. Available wherever the harness can
  spawn subagents.
- **Tier 2 (optional accelerator):** a host CLI/script vision gateway if one
  exists — probed and paced per its own protocol, never assumed present; its
  absence degrades nothing.
- **Tier 3 (final fallback):** no vision-capable subagent and no gateway —
  the judging agent reads the banked images itself and self-executes the
  banked judging procedure: same frozen template and context channels, same
  verdict law, verdict verbatim from the judged body, self-execution
  disclosed in the run report. An agent with no vision of its own cannot
  judge — report the impossibility, never fabricate a verdict.

Invariants across tiers: probes before expensive calls, degeneracy counters
on, transcripts banked to files, no image bytes in orchestrator context
(tier 3 excepts this by construction — the self-executing judge is the
reader), and the gateway key (if any) never passes through agent context.
Details: references/vision-gateway.md.

## References

- `references/verdict-law.md` — PASS semantics, the failed-read taxonomy,
  retry budgets, verdict-line formats, the sign-off channel.
- `references/judge-prompt-patterns.md` — frozen versioned templates,
  ground-rules prelude, content anchoring, probe-then-judge, two-pass
  forensic reading, the pattern-vocabulary mechanism.
- `references/rubric-axes.md` — the six scoring axes, thresholds, plateau
  calibration, inspector output contract, declared per-project adaptation,
  the 12-axis audit alternative, the strengths register.
- `references/capture-protocol.md` — state-verified capture across three
  lanes, the objective pre-check gate, capture-race taxonomy, staleness
  rules.
- `references/defect-register.md` — defect line format, dispositions, the
  pixel and DOM arbiters, false-positive families, the re-inspection ledger,
  fix waves.
- `references/vision-gateway.md` — the vision access contract, fallback
  ladder, routing law, pacing, crash-safety banking, dense-region crop
  comparison.
- `references/launch-gates.md` — set-level closeout (PASS-CHAIN, the
  certified-set registry, live state re-query), launch-gate matrices with
  structured halt payloads and stage-granular resume, the assembly/merge
  gate, cascade re-judging after upstream patches, duplicate and
  derived-target judging, banked re-run discipline.
- `references/evidence-discipline.md` — the exhaustive defect-hunting sweep
  with clean-checked and skip-proof markers, per-report uncertainties with
  settle-conditions, positive-control gate validation, the checker-bug
  class and instrument hygiene, gate-driver bookkeeping traps,
  negation-blind classification, resume checkpoints.
- `references/environment-discipline.md` — the judging-lane fence, the
  background-dispatch law, machine-level lock enforcement, the
  transplant/repair playbook, audit-lane scoping.
