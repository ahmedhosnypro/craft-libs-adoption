# Rubric axes — scoring law

## Six core axes

Scored 0-10 each; total = mean:

1. **Hierarchy & layout** — eye guidance: title → sections → actions in
   sensible order.
2. **Spacing & alignment** — consistent paddings; a shared rhythm; no
   accidental gutters or dead bands.
3. **Typography** — heading/label/caption scale, weight contrast, no
   cramped or oversized text. On right-to-left captures: bidi-correct
   rendering — no broken Arabic shaping, ellipsis on the inline-end side.
4. **Color & theming** — semantic color usage (success/error/info in roles
   that make sense); tokens, not ad-hoc colors; the palette renders — no
   unstyled or raw elements.
5. **Control affordance** — buttons/inputs look interactive and equal in
   quality; selected/checked states unambiguous; empty/placeholder states
   deliberately composed.
6. **Responsiveness for THIS viewport** — no overflow, no dead space,
   purposeful reflow; holds at the narrowest supported width with no
   clipping. On right-to-left captures: the layout actually mirrors — no
   stuck left/right regions.

- READY = mean ≥ 9.5; NEEDS FIXES otherwise.
- Contrast failures are HIGH on the color axis, never cosmetic.
- A dark-mode pass is optional where the target has one; record whether it
  ran.
- A blank, error, or login image is a CAPTURE failure, never a surface
  defect — it is never scored as a broken surface
  (references/capture-protocol.md).

## Right-to-left / i18n checklist (Arabic captures)

Applied on top of the axes when the capture locale is AR; each failure
lands on the axis it owns:

1. Layout mirrors end-to-end: nav/drawer on the mirrored side; breadcrumbs
   and chevrons flipped; steppers flow right-to-left.
2. Directional icons (arrows, back/forward) mirror; neutral icons (check,
   search, settings) do not.
3. Text is start-aligned — no hard left-justified Arabic paragraphs; no
   clipped or overlapping Arabic glyphs.
4. Numerals and dates follow ONE consistent locale decision per screen —
   no mixed digit formats.
5. Physical left/right spacing artifacts: symmetric paddings stay
   symmetric; asymmetric ones mirror.

On LTR captures the checklist is not a defect source: a layout choice that
would obviously break under ~30% longer translated strings or under RTL is
an `[i18n-risk]` observation — the same finding-line shape with the tag in
place of severity (references/defect-register.md). Never charge it as a
defect on an LTR capture.

## Score what EXISTS

- The audit scores the PRESENTATION of what is visible — never "wrong"
  names, dates, counts, or data correctness: on-screen data may be
  fixture/placeholder, and fixture content is not a defect.
- Missing features are structure deltas, not findings. Structure deltas go
  on a separate line and never reduce axis scores: a rubric coupled to
  structure turns pixel-perfect surfaces into low verdicts dominated by
  out-of-scope redesign wishes. Say both laws twice in the inspector
  prompt.
- Scoring presupposes existence: a target that is not implemented or not
  renderable cannot be scored — polishing an unbuilt feature produces
  beautiful lies. Verify the target is implemented and renderable before
  spending the capture matrix; a failed existence check stops the run and
  reports, never scores stubs.
- A comparison target is an imagination aid: STRUCTURE ONLY, never colors;
  its row data is fake and never leaks into any deliverable; on conflicts,
  the spec and docs win.
- No target image → skip the phase, record the skip, never invent a
  comparison target.

## Inspector output contract

Fixed structure, always:

```
LOCALE: <locale>  VIEWPORT: <w>x<h>  SCHEME: <scheme>
AXIS SCORES: hierarchy <n>/10 | spacing <n>/10 | typography <n>/10 |
color <n>/10 | affordance <n>/10 | responsiveness <n>/10
TOTAL: <mean>/10
FINDINGS:
- [HIGH|MEDIUM|LOW] <element> — <defect> — <concrete fix>
VERDICT: READY|NEEDS FIXES (<mean>/10)
```

- The concrete fix must be actionable blind — the fixer has not seen the
  image.
- Verify a claim with a region crop of the same image before reporting it;
  otherwise keep quiet (references/vision-gateway.md).
- Findings then go to arbitration, which may dismiss them
  (references/defect-register.md).

## Severity and confidence anchors

A finding line carries one severity and one confidence
(references/defect-register.md):

- BLOCKER — fails its purpose or looks broken: unreadable text, overlap,
  zero-width pane. Reserved for unusable-output defects.
- MAJOR — no professional would ship it: broken grid, inverted hierarchy,
  theme inconsistency. The inspector contract's HIGH lands here.
- MINOR — polish-level: pixel drift, radius mismatch. MEDIUM lands here.
- NIT — taste. LOW lands here.

Confidence:

- high — clearly visible, unambiguous.
- med — likely but partly ambiguous.
- low — suspected only; flagged so a human can verify.

Never omit a suspicion, never inflate one.

## Plateau calibration

Inspectors score in integer steps and reserve 10 for flawless; totals
plateau around 9.0 to 9.2 even when every finding was fixed or disproven.
At the plateau the dominant noise class is findings that contradict earlier
passes on UNCHANGED pixels — the contradiction signature: verdict flips
within ~0.4, "missing" elements a measurement shows present.

At the plateau: run arbitration BEFORE any fix wave; close via the
accepted-debt clause instead of looping. An inspector that still contradicts
recorded evidence is re-dismissed on the same measurement, not "fixed"
(references/defect-register.md).

## Per-model noise calibration

- Calibrate the judge MODEL before looping: two passes over the same
  capture set, scored on surfaces later adjudicated clean, measure that
  model's envelope — mean, ceiling, and pass-to-pass swing.
- A measured harsh-model envelope: mean 6.3, ceiling 8.5, zero surfaces
  READY — and the same unchanged DOM swinging ±2 between passes (one
  surface 7.5 → 4.5 with zero code change on that layout).
- The plateau contradiction signature (verdict flips within ~0.4) describes
  well-behaved inspectors at the plateau; it under-covers harsh models,
  whose noise band is far wider. Applying the 0.4 signature to a harsh
  model reads large noise flips as signal.
- Harsh means nothing missed, not low scores everywhere: handle a harsh
  model with arbitration and the one-fix-wave budget, never score-chasing.
  Pixel-prove the real defects, dismiss the DOM-disproven families, and
  record by-design contract choices as accepted debt — a model that docks
  taste-level opinions never reaches the READY bar, and the debt clause is
  the close, not more loops.
- Record each model's measured envelope (mean, ceiling, swing) as model
  reliability notes in the outcome so later rounds reuse the calibration
  instead of re-deriving it.

## Accepted debt

Per item, DUAL justification recorded: (a) why it cannot reach 10, and (b)
why it is acceptable to ship. Anything degrading perceived quality is NOT
cosmetic — fix wave regardless of its severity label. Accepted debt is
banked visibly in the outcome file, never silently.

## Declared per-project adaptation

The six-axis core is the default. Per-project adaptation is a first-class
DECLARED channel, not an improvised rider on every call: the caller supplies
axis overrides, weights, threshold, plus VIEW/CAPTURE/FACTS lines before the
first judge call; undeclared means default core. The declaration is recorded
in the outcome header so later rounds reproduce the same rubric.

## Audit-style alternative: 12 calibrated axes

For open-ended image audits (artwork, composition, brand review, non-UI
targets), a 12-axis 0-10 card replaces the six core axes. Score every axis
0-10 with one sentence of justification:

1. **Theme & dark-mode** — professional, standard theme quality; surface
   elevation steps progressively lighter as layers stack; no gray-on-gray
   body text; accents do not vibrate against the background; borders make
   subtle surface shifts, not gridline noise.
2. **Typography** — sizes legible for the audience (flag anything under
   ~11px); scale and weight contrast; no clashing families, no mono where
   prose belongs, no ALL-CAPS overuse, consistent capitalization across
   sibling labels.
3. **Spacing** — no cramped or bloated gaps; no doubled or missing
   hairlines; consistent vertical rhythm; nothing touching that should
   not; no dead air beside crowding.
4. **Alignment** — baselines line up; centered elements are centered;
   columns are not ragged; sibling edges align; icons optically align
   with their text.
5. **Crowding & density** — no overstuffed regions, no competing focal
   points, breathing room preserved.
6. **Hierarchy** — the eye is guided; primary, secondary, and tertiary
   tiers are distinct; the intended focal point wins.
7. **Composition** — pane proportions balanced; no dead space, orphaned
   or stranded elements; every region reads as the same app.
8. **Completeness** — no clipped or cut-off text, squashed or zero-width
   elements, overlaps, lost containers, or stray horizontal scrollbars.
9. **Continuity & consistency** — corner radii, border thicknesses, shadow
   treatments, icon styles, and same-kind controls consistent across
   regions.
10. **Affordance & states** — clickable looks clickable and static looks
    static; disabled distinguishable from enabled; selected/active
    visibly marked; empty states composed; status never carried by color
    alone.
11. **First-glance clarity** — what a brand-new user understands within 3
    seconds; the 2-3 actions the screen offers are actually visible at
    first glance; given the injected VIEW purpose, the intended focal
    point wins the eye.
12. **Overall** — "would I show this to a user?" — NOT the average of the
    axes.

Anchors, all axes:

- 10 = ship it; the forensic pass found nothing.
- 8 = minor polish only; nothing a user would consciously notice.
- 6 = presentable but visibly unrefined; issues a user feels but cannot
  name.
- 4 = amateurish; compounding issues that erode trust.
- 2 = broken hierarchy or illegibility; the screen fights the user.
- 0 = unusable.

Odd numbers interpolate. Use the full range — do not cluster in 5-7.

The scores stand on a hunting pass that walks the exhaustive category set
with explicit clean-category markers (references/evidence-discipline.md);
every finding line carries severity plus confidence per the anchors above.

## Strengths register

Non-defect audits (composition, artwork scoring, brand review) register
STRENGTHS with the same discipline as defects: 2-4 things the view already
does well, specific and located like defects, each severity- and
confidence-tagged and evidence-linked. Strengths calibrate the criticism —
if none can be named, say so instead of inventing them. An audit that
lists only weaknesses is half an audit.
