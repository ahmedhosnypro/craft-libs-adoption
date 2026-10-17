# Verdict law — what counts as a verdict

Audience: every worker that reads a judge/inspector transcript or records a
verdict. The judge layer produces text; this file decides what that text
means.

## Three states, never two

Every judge call ends in exactly one of:

- **PASS** — certified; bank it and close the row.
- **FAIL** — defects charged; feed the fix loop.
- **NO-RESULT** — the read failed (taxonomy below); not evidence for or
  against anything. NO-RESULT rows stay re-probable and are never silently
  skipped: a hidden failure is worse than a crash.

Definiteness is a separate question from pass/fail: a definite row can be
PASS or FAIL, and only definite rows count as progress. Counter discipline
makes that true: a blank or degenerate observation is banked NO-RESULT
(with its reason, e.g. `noResult="blank-document"`), retried once in
flight, and kept OUT of every done/progress counter so a later run
re-probes it. Rows whose blank or degenerate bodies were counted as
definite were silently skipped by every resume until a fresh session
re-probed them. Any observation that is not a real observation of the
target — no probe field, a thrown exception, a blank or degenerate capture,
a screenshot of a window that never drew — is NO-RESULT and stays
re-probable. A blank capture from a stale served state is the different,
capture-race case: hold and retry, never a finding
(references/capture-protocol.md).

## PASS law

A PASS exists only as a banked transcript with BOTH:

1. a coherent body — the model demonstrably inspected the actual subject:
   ground-rule acknowledgments, quoted artifacts, defect dispositions; and
2. an explicit terminal verdict line in the fixed format for the mode.

- A worker's or peer's "looks good" is not a verdict.
- Timeout, empty stream, probe-only read, or degenerate garbage is a failed
  attempt, never a PASS.
- A verdict obtained with a factually wrong prompt anchor is VOID even when
  it says PASS — fix the anchor, re-judge.
- A PASS obtained without the ground-rules prelude is void — re-judge with
  it.
- Wording latitude: a non-standard closing ("IMG1 is BETTER") is a valid
  verdict when the body is structurally complete; a demanded closing line
  the model ignored does not void an otherwise complete body — adjudicate
  by content. The winner body of a comparison must NAME the winning image
  explicitly, by its declared capture label (IMG1/IMG2 are declared per
  capture; adjudication is order-independent). An affirmation of fidelity
  with no verdict token and no named winner certifies nothing.
- A bare `PASS` token is a VALID verdict even when it falls under a length
  floor — a length floor is not a coherence test, and a floor that
  mislabels a bare PASS as degenerate or deferred is the bug. The
  degeneracy gate is asymmetric: a bare `FAIL` with zero quoted findings is
  information-free → failed read (one paced retry). A plain transcription
  with no verdict word whose every expected string is present and verbatim
  is adjudicated by content and counts PASS — the paced-retry budget is
  for garbage bodies, not missing formatting.
- The verdict counts the VISIBLE state, not source correctness: text
  present in the DOM but amputated mid-glyph by its own container or an
  overlapping band (clipped-but-present) is a finding — a full string
  behind a 4.5px visible sliver is a defect. Judgment on such a shot covers
  only the visible sliver; the hidden remainder is not adjudicable from it.
  Retake with the region's full geometry rather than guessing about hidden
  content.
- **Banked-PASS is terminal.** On resume: verify — never re-judge certified
  pixels. Verify = deliverable hash unchanged, transcript chain intact, the
  log carries a real winner marker (a dead leg still writes its
  route/metadata header), and where the deliverable is rebuildable, fresh
  render ≡ banked render (0-diff), build hash match, chrome check.
  Terminality has these exceptions:
  - A banked PASS can be PRE-DEFECT: the defect report, not the outcome
    row, is the state of record. A PASS older than a known defect is
    stale; clear stale repair notes referencing superseded transcripts at
    certification.
  - Editing a certified component re-opens EVERY descendant — terminality
    yields to the cascade: rebuild and re-judge the subtree, or leave the
    component alone and express the change in the child's delta.
  - Certificate validity never depends on authorship: after long runs,
    "who wrote this" attributions are unreliable — enumerate every
    candidate writer INCLUDING yourself before treating fresh artifacts as
    a peer's, and verify the transcript + store independently.
  - A visible divergence re-OPENS the certified row.
  - A detected peer on a terminal row is converged with, never fought:
    verify the banked state independently and report the race.
- A judge PASS never overrides measured evidence against ground truth:
  visible deviation is a finding even over a PASS.

### Text-free components — the geometry PASS route

A component that renders no copy and no SVG by design (progress bars,
skeletons, canvas surfaces) cannot be adjudicated by text presence; a
text-or-SVG predicate false-FAILs a correct render. The verdict predicate
accepts, in addition to text/SVG:

- **DOM geometry** — at least one visible child/descendant box ≥4 px²
  inside the target root, respecting `display` / `visibility` / `opacity`;
  one line in the live probe.
- **Non-blank pixels** — content pixels beyond the frame's background,
  count ≥32 and bbox ≥2×2; decidable OFFLINE from the banked PNG. For
  non-DOM targets (artwork, native raster) this is the workhorse.

Both routes were calibrated on a progress bar whose DOM measured
track 736×3 / fill 478×3 = 64.9%, agreeing with the declared 0.65 and a
pixel measurement of 65.0% on the same banked PNG.

## Failed-read taxonomy — classify the body BEFORE reacting

1. **TIMEOUT** — the outer wrapper exited on its wall. Failed read, not a
   verdict.
2. **DEGENERATE BODY** — word-salad, `!!!!` spam, looping text. No
   evidentiary value; re-invoke with identical parameters and a new attempt
   number.
3. **OFF-TOPIC CHAT** — greetings or questions instead of findings. One
   paced retry whose prompt adds: "output ONLY the inspection findings — do
   NOT introduce yourself, ask questions, or chat".
4. **SELF-REFUTING BODY** — opens with "DEFECTS FOUND", retracts, closes
   clean. Information-bearing: gate on the FINAL conclusion, not the header.
5. **CORRUPTED-BUT-VALID** — `PASS!!!!!!!!!!` is filler appended AFTER a
   real verdict token: check for the token, do not discard the read. A bare
   `PASS` under a length floor is VALID (see PASS law); the failed-read
   member of this family is the bare `FAIL` with zero quoted findings.
6. **HALLUCINATED VERDICT** — fluent, decisive, wrong about artifacts that
   do not exist. Verify the QUOTED artifacts first (tokens, computed
   styles, coordinates); refute by measurement without a re-run.
7. **EXIT-0 LIES** — a gateway or gate tool can exit 0 and print "analyzed
   successfully" over garbage. Read every result file; success claims are
   not bodies. A multi-file gate invocation can silently gate only the
   LAST positional file and still exit 0 — run it once per file and
   require exit 0 on each; a formatter can re-expand after the linter
   passed, so require two consecutive green runs, the second over the
   canonical form; under concurrent lanes the per-file gate, not the
   whole-project check, is the gate.
8. **DEGENERACY-DETECTION TRAPS** — strip log-prefix lines (`[info]`,
   `[winner]`) before any character-diversity check; judge the body after
   the last `===` header; naive validators pass all-bang bodies; reject
   bodies whose non-punctuation alphabet is too thin to be a transcription
   (a few real words padded with `!!!!` passes naive length floors); an
   informative-looking prefix + bang filler (`INS!!!!`, `STRUCT!!!!`) is a
   failed read, not a heading.
9. **COHERENT-BUT-FALSE NUMBERS** — confident numbers contradicted by
   measurement. Defective evidence like garbage: measure first, bank the
   numeric rebuttal, re-run at better conditioning.
10. **ECHO-CLASS DEGENERATES** — HTTP-200 garbage that parrots the prompt:
    long verbatim prompt spans, glossary dumps, section-header shells, zero
    section coverage. Calibrate the detector on known-good transcripts
    first: legitimate audits quote very little of the prompt, true echoes
    quote most of it; flag only above the calibrated coverage gate.
11. **MISFIRE** — the dispatch ran without the exact frozen payload (the
    prompt argument omitted), so the gateway answered its DEFAULT prompt:
    coherent, and worth nothing as a verdict. A judge call without its
    exact payload is a misfire, not a verdict — always source the payload
    from the banked prompt file byte-for-byte (or write it to a file and
    pass its contents). Valueless context flags abort with an argument
    error BEFORE any model call — check the dispatch log for that argument
    error before blaming the model. Misfires stay banked as spent evidence
    with an explicit caveat, never counted as verdicts; the attempt is
    spent.

An in-band error marker (`<ERROR: ...>`) inside an otherwise usable
transcript is preserved, not laundered; such a transcript feeds
measurement, never a verdict.

## Retry budgets — bounded, paced, honest

- Per target: up to 3 garbage re-invokes (a degenerate output means the call
  did not happen) and 6 judge attempts; then PARK the row as failed for
  review — never a silent drop.
- Gateway or endpoint failure: wait ~120s, ONE paced retry, then mark the
  row DEFERRED (gateway) and move on. Run the pacing sleep and the retried
  call as separate invocations so a harness timeout cannot abort the retry.
  If your OWN harness did abort the call mid-flight, that is not a second
  failed read: re-issuing the call alone (full budget, no sleep) is still
  the ONE legal paced retry.
- Failed reads get the paced retry, NEVER a re-capture — the capture was
  already proven good, and tall retakes can manufacture a second, different
  FAIL on the same target.
- Retry demand clusters at run edges: read-timeout waves cluster at the
  boundaries of a run (the first call after a long idle, the last/sparsest
  shot), not the middle — budget the single paced retry at both ends.
  Degenerate bodies cluster in mid-run WAVES and PAIRS.
- A spent retry budget is NOT a DEFERRED row when an informative first read
  exists and was adjudicated: the refutation stands on the DOM/pixel
  evidence alone.
- Hard-wall hang: retry ONCE under a wider wall before banking debt — a hang
  is usually a wall artifact, and that retry is part of the protocol, not an
  attempt.
- A probe failure does not invalidate an already-landed comparison: the
  probe opens the window, it is not evidence; note it in the report.
- A closed gateway window never blocks the non-vision deliverable: bank the
  debt, label the certification honestly (PENDING / single-session
  unconfirmed), re-run when the window reopens.
- Zero-fix-wave runs are valid: findings that all arbitrate to noise close
  the row via accepted debt — never manufacture fixes for disproven
  findings (references/rubric-axes.md, references/defect-register.md).

## Verdict-line formats

Fixed, machine-parseable, one per transcript, always the last content line:

- Comparison judge: `FINAL VERDICT: PASS|FAIL for '<goal phrase>'`
- Crop comparison: `CROP SUMMARY: N BLOCKER, M MAJOR, K MINOR`
- Scoring inspector: `VERDICT: READY|NEEDS FIXES (mean <n>/10)`

A coherent body that never commits — no verdict token, no named winner —
certifies nothing regardless of length. At the attempt cap with lineless
bodies, park the row with the complete failure narrative; re-dispatch
judging only (reuse the banked build and renders — no rebuild), and the
first draw carrying the terminal line certifies.

Parity is a verdict: a structure-comparison judge's winner field is
three-valued — either side or TIE. A TIE (or implementation-wins) on
structure, with the loop's own acceptance bar already met, completes the
comparison phase; parity is a definite, certifying result, not a missing
decision. Sort any "still missing" deltas into visual/copy residuals (fix
wave) versus capability deltas (route to a spec amendment, never silently
implemented — references/defect-register.md).

Every verdict also carries a leg-count label — `single-read, unconfirmed` or
`corroborated (second read: <route + single question>)`. Two contradicting
reads make a finding advisory at most, never a charged defect. When a
multi-model differential register is running, only findings with
cross-model consensus enter the final register; every other finding keeps
its finder label and waits for arbitration.

## Unrenderable targets — direct mount + equivalence proof

When the target's frame cannot be produced (rig defect), the validated
route is a DIRECT MOUNT of the target's own exported render component in
the real host context — same document, same fonts, same globals, same
viewport, importing the same module URLs the host loads, inside the same
provider/decorator wrapper. Then PROVE equivalence: force the changed
variable back to its baseline value and reproduce the recorded baseline
numbers EXACTLY; the new state is then a single-variable A/B in the same
rig. A direct mount without the equivalence proof is a new rig, not a
certificate.

A target whose contract renders NOTHING (a closed modal, an unmounted
portal) produces only a blank canvas that proves nothing — such targets are
CORRECTLY SKIPPED: the gate matrix is renderable-targets × viewports, not
all-targets × viewports. Verify the count against the target source before
calling an inherited matrix incomplete.

## Sign-off channel — ambiguity is routed, never folded

- PASS-with-MAJOR tension, split OCR votes, methodology noise: recorded as
  NOTE/sign-off items addressed to the human — never silently into the
  verdict, never silently out of the report.
- Measurement noise and product defects get separate dispositions.
- A sub-threshold screen result certifies only as a documented deviation —
  never a silent pass, and never a silent re-run of the screen to dodge
  the number.
- Human preference chooses WHICH candidate ships; it cannot waive the gate.
  Preference and verdict are separate channels.
