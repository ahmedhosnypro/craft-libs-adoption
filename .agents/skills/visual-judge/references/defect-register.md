# Defect register — findings, dispositions, arbitration

A judge or inspector finding is a LEAD, never a verdict. Every finding is
arbitrated against objective measurement before it counts; a disproven
finding is DISMISSED, never "fixed", never accepted debt.

## Charging standard: LOOKS-WRONG = flag

- Flag everything that looks wrong, even slightly; never assume a visible
  anomaly is intentional.
- A missed defect is worse than a false alarm — but a "false alarm" means a
  real, visible anomaly whose severity is debatable, never an invented
  element.
- The standard is "LOOKS WRONG = flag", not "DOM-correct = pass": a full
  string visible only as a ~4.5px sliver is a defect. A measurement that
  proves an element exists does not dismiss a claim about how it renders —
  adjudicate the rendered claim with rendered evidence.

## Defect line format

```
- [BLOCKER|MAJOR|MINOR|NIT|confidence: high|med|low] <region> › <position> — <what> — <why it matters> — <fix hint>
```

- Region comes from the judge's layout map; position is specific (corner,
  edge, offset).
- DEDUP: one root cause = one entry, however many reads reported it.
- The inspector's HIGH/MEDIUM/LOW maps to MAJOR/MINOR/NIT; BLOCKER is
  reserved for unusable-output defects (missing elements, wrong table
  data).
- `[i18n-risk]` is a marker class in the same line shape, marker in place
  of severity: a forward-looking hazard that breaks under ~30% longer
  translated strings or RTL — an observation, not a current defect, and
  never a scoring axis. Example shape: a label already wrapping to 2 lines
  at the source-language length will triple-wrap or clip at +30%
  translation length in a fixed-height track.

## Dispositions

Every charged defect is classified WITH its measurement:

- **REAL** — measurement confirms; goes to the fix wave.
- **HALLUCINATED** — measurement refutes; recorded as refuted (tag + probe
  + result) so later rounds discount it.
- **DEBATABLE** — a judgment call; routed to the sign-off channel with the
  evidence (references/verdict-law.md).

Route counting is not evidence: several winning transcripts can all
describe the WRONG subject. Read what the transcript SAYS about the
subject, not that a winner exists.

## The arbiters

**Pixel arbiter** (rendered artifacts, images, documents):

- Vision coordinate estimates can be off by tens of pixels — pixels win on
  every conflict.
- A single-read claim without pixel confirmation is rejected: one read plus
  no measured ink = SKIP; refuted reads are recorded as refuted.
- A judge PASS does not override measured geometry; owner feedback on
  placement overrides the judge.
- Judge size prescriptions suffer resolution bias — translate them to the
  original's raw pixel space and measure before spending the next attempt.
- Machine checks green but the judge FAILs: pixel-verify each MAJOR against
  the original first; disproven MAJORs ride into the judge's FACTS context
  on the retry — never self-certify.
- A judge MAJOR on pixels byte-identical to a prior certified build is judge
  variance — measure before obeying.
- Small-text color claims: pixel column profiles are the arbiter; a
  full-image vision read is NOT evidence for small-text color.
- Vision-external artifacts (cursors, player chrome, watermarks) get their
  own disposition class: correctly omitted = not a defect.

Calibrated measurement doctrine (rendered artifacts — numbers, not vibes):

- Closed-loop tolerance is ~4px at 150dpi render scale; verify ink edges
  within it BEFORE judging.
- Identical-window self-targets: derive expected values by running the SAME
  predicates and windows on the reference frame, so JPEG-antialias bleed
  cancels on both sides — never hardcode targets from an older note.
- Point-to-ink distance (nearest-ink tree) for strokes and curves, never
  per-row coordinate diffs — those lie on near-horizontal strokes and
  amplify sub-pixel grid offsets into phantom deviations. Sample rows where
  the stroke is locally steep, columns where it is locally flat.
- Faint-paint ink-strength hierarchy: solid strokes survive encoding dark
  (same-frame control strokes measure the floor); a window holding ZERO
  sub-170-luminance pixels was genuinely faint paint in the source; rescan
  a faint stroke's extent with a loose lum<225 threshold — encoding erodes
  faint tips, so the visible extent under-reads the true one.
- Absence checks: absence of ink under strict masks is not absence of ink —
  1px anti-aliased strokes dilute below every threshold. Scan with a
  sensitive mask (max channel deviation from white > 25) plus one gated
  4-5x high-zoom read before declaring a thin/small element absent.
- 600dpi signflip discriminator: never diagnose stroke wobble from a
  150dpi centerline trace alone (anti-aliasing masks or fakes it) — trace
  at 600dpi and count 1px edge signflips per edge.
- Threshold-geometry: pixel-COUNT comparisons across scales are invalid
  (AA profiles differ by scale) — use native-resolution luminance transects
  plus calibrated scale conversion, never counts.
- Occluded or partially visible elements: a vision read of the occluded
  artifact is a prior, not evidence. The arbiter is a fixed-window pixel
  comparison against same-class known references (sibling glyphs) at a
  STRUCTURALLY located position — never a color centroid; a polluted
  location voids the measurement. ALWAYS test the strongest alternative
  hypothesis; a discriminating measurement that "confirms" the hypothesis
  is void if the window was polluted or the alternative never tested.

**DOM arbiter** (live web UI):

- `getComputedStyle` — token values are the truth; raster estimates are
  not.
- `getBoundingClientRect` — sizes, centering, presence.
- Text-range rects for bidi claims; `textContent` codepoint dumps for copy
  claims.
- Contrast is COMPUTED (WCAG), never eyeballed — a vision read's contrast
  number is not a measurement.
- Adjudicate the hiding WRAPPER, not its child: a `display: none` descendant
  still returns its own computed display.
- Run measurements against the live target through the harness's
  browser-eval facility, or the browser devtools console — never from
  memory.

Counterweight: vision CAN catch real character-level defects that
measurements miss — the odd read out is not always the wrong one.
Adjudicate with `textContent` first, then believe the outlier.

## Raster-inherent misreads — never loop re-captures

- A sub-30px monospace glyph can misread PERSISTENTLY (digit `0` read as
  `8`) on the original AND on a fresh re-capture + re-run: the misread is
  in the RASTER, not the pipeline. The codepoint/textContent dump is the
  verdict — adjudicate from it, never change code for it, never loop
  re-captures. Pre-anchor the true character ("the second character is the
  DIGIT ZERO, not an eight") in the first prompt for any small mono text
  carrying a confusable glyph.
- One fresh re-capture + one re-run clears pipeline noise; it does not
  clear raster-inherent misreads. Classify which class you are in BEFORE
  spending a recapture.
- At small label sizes a substituted font's heavy stroke weight merges
  adjacent letters into blobs — vision then reports truncation while every
  glyph is present. Measure stroke weight and check for letter-merging
  before re-wording any text.

## False-positive families — arbitrate on sight

- Sub-8px alignment claims and sub-3px centering judgments (contradictory
  across passes = the noise signature; below ~3px at capture resolution is
  not adjudicable from pixels).
- Tiny-element presence claims (the smallest elements are the least
  reliable reads).
- Shape or hue claims on small geometry (a sub-30px rounded track read as
  a pointed trapezoid at one viewport).
- Token-value aesthetic opinions — including a report that transcribes the
  text character-by-character and then calls it invisible (it contradicts
  itself); the computed token value is the truth.
- Invented text at scroll boundaries.
- Self-refuting centering arithmetic — recompute from the report's own
  numbers.
- Relative-state misreads between siblings (vision reported the wrong
  dimmed side).
- Meter/progress proportions — rect fill/track vs `aria-valuenow`; a short
  track reads full to vision at capture scale (measured: 123/192 px of
  track = aria 64%, 90/192 = 47%).
- RTL translate-based progress fills — `getBoundingClientRect().width`
  reads the FULL track when the fill is transform-based; visible fill =
  track width − |translate|; arbitrate "bar misaligned/short" claims with
  the computed transform, not the bar box.
- Digit-script claims — one codepoint-enumeration eval settles them.
- Fold-crop of scrollable pages — scroll to the bottom, measure the gap.
- Scroll-reachable overflow = by design; only out-of-frame AND unreachable
  is a defect.
- Modal-semantics delusions — a modal scored DOWN for occluding content it
  exists to occlude, "lacks a backdrop" against a DOM-verified
  `rgba(0, 0, 0, 0.5)` backdrop element, phantom dialog states. Arbitrate
  EVERY backdrop/centering/occlusion claim against computed styles.
- Webfont fallback shaping — an isolated story-rig frame may not receive
  the app's webfont CSS variables, so script shaping/tracking claims from
  such captures are fallback-font artifacts until computed styles (font
  family, letter-spacing) confirm them.
- Segment-boundary misattribution — an icon at a segment's inner edge
  attributed to the NEIGHBOR segment ("neighbor has the icon, this one
  lacks one"); one DOM count of leading-icon nodes per segment disproves
  both halves.
- Wrapper-not-child visibility claims — a descendant of `display: none`
  still returns its own computed display; adjudicate the hiding wrapper.
- RTL inline-end confusion — "element on the wrong left side" under an RTL
  locale: left IS the inline-end; space-between headers mirror correctly;
  dismiss by logical-property reasoning, never by moving pixels.
- Odd-viewport-out counterweight — when one viewport of a multi-viewport
  set quotes mangled text the others silently miss (or mis-shapes a small
  element the others pass), adjudicate the odd read out with
  `textContent` before calling it a hallucination; majority silence is not
  refutation.

Adjudicate claim-by-claim, never report-by-report: a true positive can
arrive packaged with false claims.

## Report register skeleton

A defect report is a fixed-shape register, not a findings dump. Sections,
in order:

1. **Layout map** — every region/pane/control cluster, each with a short
   name; these names are the canonical references every defect cites
   (region › position). Close with the capture's scale/quality limits
   (blur, crop, compression, fallback fonts) that condition severity.
2. **First-glance test** — what a brand-new user understands within 3
   seconds; the 2-3 actions the surface appears to offer; what SHOULD win
   the eye and whether it does.
3. **Strengths** — 2-4 specific, located strengths; this calibrates the
   criticism. Invented strengths are findings too.
4. **Defect list** — the exhaustive category sweep with every category
   closed by defect lines or an explicit proof marker ("clean — checked,
   nothing found" / "skip: none present") —
   references/evidence-discipline.md.
5. **Top 3** — the three defects that most damage perceived quality or
   usability, ranked, one line each, cross-referenced to their defect-list
   lines.
6. **Structural proposal** — at most 3 moves, ranked by impact: every move
   names source → destination using layout-map region names, with the
   impact rationale. Reorganize only what is visible and in scope;
   anything needing off-screen functionality is one `[out-of-scope]` line;
   missing features are defect-list findings, not redesigns. "No
   structural reorganization warranted" is a valid outcome.
7. **Verdict** — per-axis score with a one-line justification each;
   "overall" is a would-I-show-this-to-a-user judgment, not the mean.
8. **Uncertainties** — assumptions, static-capture limits, low-confidence
   flags, and the settle-condition that would resolve each.
9. **Vocabulary proposals** — generalizable new patterns only; an explicit
   "no additions" when empty.

Register mechanics:

- The written register lists consensus findings first, then adjudicated
  unique findings — each naming the finder model and its measurement — and
  cites file paths: every charged defect names the evidence artifact
  (transcript, measurement, capture) that grounds it.
- Non-UI targets (artwork, photography, crops of a larger piece) get a
  declared category mapping up front — map the UI category set onto the
  target's own axes once, in the prompt header, instead of improvising per
  finding; improvised mappings produced refused axes and vacuous scores.
  Crop and fragment boundaries are capture artifacts, never defects.

## DEFECTS table

The verdict-durability pattern — every row evidence-linked, method stated
up front, three sections:

- **Method block first**: which reads, crops, and pixel scans produced the
  table, and the arbiter precedence ("pixel measurement wins on every
  conflict" — vision coordinate estimates ran up to 40px off).
- **Verified defects** (evidence-linked): per row — region, measured
  original truth, current state, fix.
- **Judged-but-kept**: confirmed-correct items kept, with the reason.
- **Unverified / rejected**: refuted reads, each naming the measurement
  that refuted it; one read plus no measured ink = SKIP.

Nothing is charged without a measurement or a multi-read agreement.

## Structure deltas and comparison verdicts

- Skeleton, not labels: comparison verdicts rest on the layout skeleton,
  never on vision-read label text — reads paraphrase and hallucinate labels
  (especially non-Latin scripts). Ground-truth structure lists against the
  component source or DOM state guards before verdicting.
- Delta routing: sort "still missing vs the prototype" deltas into pure
  visual/copy (implementable directly by a fix wave) and new capabilities
  (fields, queries, surfaces, schema — a spec-amendment decision held by
  the owner, NEVER silently implemented). A capability delta that never
  routes to a spec decision is silent scope creep.

## Fix waves

- Cluster findings by shared files; one fixer per DISJOINT file set;
  foreign pre-existing failures are recorded, never fixed.
- Fixers receive findings VERBATIM, plus project conventions, plus a
  per-file quality gate requirement.
- Findings route through canonical recipes; a finding with no matching
  recipe is reported as a gap (a playbook candidate), never improvised
  silently.
- Shared-primitive findings are cross-file decisions escalated to the
  orchestrator, not silent local edits.
- ONE fix-loop cycle per defect: fix, re-verify, then report residuals —
  never loop.
- After a charged defect is fixed, expect the re-judge's freed attention to
  land on the NEXT-weakest element — pre-audit inherited and unmeasured
  geometry BEFORE the re-judge, not after the next FAIL.
- Zero-fix-wave runs are valid: all-noise findings close via accepted debt
  (references/rubric-axes.md).
