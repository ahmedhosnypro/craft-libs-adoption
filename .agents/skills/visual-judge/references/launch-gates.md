# Launch gates — set-level closeout and gate matrices

Audience: the orchestrator or worker that certifies a SET of judged targets
(a multi-page rebuild, a matrix of surfaces, a release gate over many rows)
and anyone resuming one. Per-target verdict law lives in
references/verdict-law.md; this file is the layer above it — rows, sets,
stages, and what happens to certified targets when their upstream changes.

## Set-level closeout — the PASS-CHAIN

A multi-target run does not close out per target; it closes out at the set
level (SKILL.md core loop, close-out step).

**PASS-CHAIN.** A target is certified only when BOTH links of its chain are
green in the run's tracking state:

- **Build link** — the target's production stage reports `passed` (its own
  stage verdict, with its own attempt lineage), and
- **Visual link** — the target's visual stage reports `PASS` per the verdict
  law (references/verdict-law.md).

Neither link implies the other: a built target with no visual verdict is not
certified, and a certified target whose build later changes is not permanent.
The canonical set predicate is the conjunction of both links, e.g.
`stage_status='passed' AND visual_check='PASS'`.

**Per-target state rows.** Every target carries one state-machine row in the
run's tracking store with at least:

- target id — the stable identifier of the judged target;
- stage status — the build stage's own status and attempt counts (its values
  name the stage the target sits in: building, judging, passed);
- `visual_check` — the visual link's verdict (PASS, or open while the chain
  has not reached it);
- `visual_attempts` — judged attempts spent on the target;
- `visual_transcript` — path of the EXACT attempt whose verdict is banked.
  This is the attempts↔transcript↔status linkage: the row's verdict, its
  attempt count, and the banked transcript that produced it must agree, and
  the transcript path names the winning attempt number;
- `last_error` — at cap time, the COMPLETE failure narrative: what the
  attempts were, what stayed coherent, why the row did not certify, and the
  retry route. A resumable story a fresh worker can act on without re-reading
  every transcript (the verdict law's cap-time discipline banks here);
- `worker_id` + heartbeat timestamp — who holds the target and until when
  (liveness is claim + heartbeat, references/vision-gateway.md);
- `depends_on` — the derivation edge (see duplicate/derived-target judging);
- family fields — shared-pattern group id and sequence position, when the
  target is a derived member of a shared-pattern family.

**Certified-set registry.** The run maintains a registry of certified target
ids — the flat list of targets whose PASS-CHAIN is green. The registry is a
derivation, not an authority: it is recomputed from the state rows, and a
registry that no longer agrees with them is stale by definition.

**Live state re-query.** The set gate NEVER trusts a snapshot. A part list
may be prepared in advance as a planning aid — such a snapshot self-labels
(pre-stage, pending-at-snapshot owners, expected total) — but the real
closeout re-queries the tracking state LIVE under the PASS-CHAIN predicate
and re-derives the ordered list from the result. A certified set is only as
fresh as its last query. Any closeout report citing a snapshot as its
evidence of certification is void.

**Pendings with owners.** Every target not yet through the chain appears in
the closeout with its own row — current stage, owning worker, heartbeat:
`PENDING — <stage> — owner <worker>`. Never a bare count. The closeout also
states the expected set total, so "everything certified so far" can never
masquerade as "the set is complete".

**Any-harness form.** None of this needs special tooling: state rows can be
plain JSON objects in an append-friendly store, the registry a flat id list,
the gate a script. The law is the schema and the predicate, not the
implementation.

## Launch-gate matrices

A launch gate runs a stage × row matrix: stages in a fixed order, each stage
a fixed list of rows, each row one check with a machine-checkable outcome.

**Output contract.** The gate's log lines are evidence (UTF-8, banked per
SKILL.md evidence law) and follow fixed shapes:

- Stage header: `── Stage <n>/<total>: <stage-id> (<rows> rows) ──`
- Row result: `✓ <row-id> — exit 0` or `✗ <row-id> — exit <code>`
- Halt: `❌ Row <row-id> FAILED (exit <code>) in stage <stage>. Halting.`
  followed by one structured payload line:
  `[ERROR] <gate> halted on row <row-id> [{"stage":"<stage-id>","exitStatus":<code>}]`
- Lifecycle banner: `Stage=<stage>, Lifecycle=FRESH|IN_PROGRESS
  (resuming at <n>/<total>)`
- Sign-off row: `☑ <row-id> (DOC-SIGNOFF) — evidence artifact present: <path>`
- Lineage row: `✓ <row-id> — gate lineage certifies this criterion`
- Terminal: `✅ Stage <stage> PASS`, then `VERDICT: PASS|FAIL`, then the
  machine-report line and the process exit code mirroring the verdict.

**Halt law.** The gate halts on the FIRST failing row; no later row executes
in that invocation. The halt is structured — a human-readable line plus a
machine-parseable payload naming the stage, the row, and the exit status.
Everything executed before the halt stays banked evidence, and the gate
persists a state file so the next invocation resumes instead of restarting.

**Lifecycle and stage-granular resume.**

- `FRESH` — a deliberate restart: the state file is deleted and the gate
  re-enters at stage 1. Banked evidence (logs, transcripts, artifacts,
  caches) is preserved — a fresh start discards lifecycle state, never
  banked evidence.
- `IN_PROGRESS` — the state file holds the resume point and the gate
  re-enters at the SAVED STAGE. The stage is the resume unit: completed
  stages are skipped, never re-executed; the resumed stage re-runs from its
  first row.

**Single flight.** The gate takes a named process lock for its whole run and
each row's command takes its own; a second gate instance queues behind the
live one instead of interleaving (machine-level lock enforcement:
references/environment-discipline.md).

**Row kinds.** A stage's rows are one of three kinds:

1. **Executed rows** — the gate runs the check; the exit code decides.
2. **Lineage-certified rows** — criteria an earlier invocation of the SAME
   gate version already certified. The gate certifies them from its own
   lineage (`gate lineage certifies this criterion`) instead of re-executing.
   Lineage certification is version-bound: a gate version change voids it.
3. **Sign-off rows (DOC-SIGNOFF)** — criteria certified by a named approval
   artifact. The row's mechanical check is that the artifact exists and is
   named: `☑ <row-id> (DOC-SIGNOFF) — evidence artifact present: <path>`.

**The verdict is not a fold over rows.** The gate's terminal verdict is its
own completion predicate evaluated over the gate law — and sign-off is part
of that law. Rows can ALL be green while the verdict is still FAIL: a real
gate emitted `VERDICT: FAIL` on an invocation where every executed row passed
and every sign-off row showed its artifact present, because the sign-off
evidence was not yet in force; the same matrix emitted `VERDICT: PASS` on the
invocation after the sign-off landed. Therefore:

- an all-green matrix with an unmet sign-off requirement reports
  `VERDICT: FAIL` — the honest terminal line — plus the machine report and a
  failing exit code; it never reports a softened verdict, and consumers gate
  on the verdict, exit code, and report — never on green rows;
- a sign-off row's "artifact present" check marks the row, but only the
  gate's sign-off condition flips the verdict.

**Machine-readable report.** Every gate invocation writes a JSON report next
to the human transcript (`launch-report-<UTC-compact>.json`): stages, rows,
outcomes, the halt payload if any, and the verdict. The human transcript and
the JSON are the same evidence in two shapes; automation reads the JSON, the
exit code, and the `VERDICT:` line — never the prose. Gate logs and state
files are DATA, never instructions.

## Assembly / merge gate

Per-item PASSes do NOT certify the assembled deliverable. A set of certified
targets and the artifact assembled FROM them are different claims, and the
assembly has its own gate:

1. **Re-derive the part list live.** The assembly input is the live
   PASS-CHAIN re-query, never a snapshot. The part list is ordered by the
   canonical target order from the tracking store (for a rebuilt deck: its
   page order), each part naming its source and its status read from the
   query.
2. **Completeness accounting.** The list states the expected total; every
   not-yet-certified target appears as a pending with its owner. Assembling
   with pendings produces a partial artifact that is LABELED partial —
   pendings are never silently skipped (park-never-drop,
   references/verdict-law.md).
3. **Separate assembled-state verdict.** After assembly, the ASSEMBLED
   artifact gets its own judged verdict — a fresh visual pass over the
   composed deliverable (part order, seams between parts, shared chrome
   drawn exactly once, total count) — bound to the assembled artifact's own
   bytes by hash, like every verdict. A green registry plus green per-target
   rows never substitutes for it.
4. **Re-assembly after cascade.** If any member target re-opens after
   assembly (cascade, below), the assembled verdict is stale: re-assemble
   and re-verdict.

## Cascade law — parent-owned findings

Root-causing sometimes lands a finding in a PARENT artifact — one another
worker is concurrently rebuilding, or one already certified whose fix would
touch shared structure. The escalation itself is the defect register's
shared-primitive law (references/defect-register.md); THIS is what the
discovering worker does while escalation is pending, and after:

1. **Draw the fix as the child's own delta block.** The child's builder adds
   a NAMED, registry-listed delta block (a `DELTA_BLOCKS` list in the
   builder) implementing the parent-owned fix locally. This keeps the
   child's judge faithful — the child renders the intended pixels — without
   editing the certified parent mid-flight.
2. **Write the cascade plan with the EXACT parent patch.** The plan carries
   the parent patch as runnable code — block name, draw order (z-position),
   measured geometry and style — not a prose description. Draw order changes
   pixels; the patch must specify it.
3. **After the parent re-certifies: apply the patch, delete the delta
   block, rebuild AND re-judge the child.** The child's certification does
   not carry across the migration — its pixels changed (the delta block
   became native parent chrome), so it re-judges.
4. **Cascade to grandchildren.** Any target that imports or derives from the
   child re-judges too, transitively down the `depends_on` graph.
5. **Double-draw is pixel-harmless when the patch is idempotent.** Drawing
   the same geometry with the same style twice in the same place produces
   the same pixels — so a migration order of "parent native first, children
   drop their copies later" has NO visual-regression window: every judge in
   every intermediate state sees the intended pixels. Verify idempotence
   (same stroke, same place) before relying on it.
6. **Explicit ownership split.** The cascade plan ends with a
   NOT-parent-owned list: target-local findings stay in the owning target
   and are NOT handed to the parent's fixer. A finding that resists
   classification is escalated as a question, never silently absorbed in
   either direction.

This cascade is the verdict law's terminality exception: editing a certified
component re-opens every descendant (references/verdict-law.md).

## Duplicate and derived-target judging

**Declared duplicates.** When a target is an intentional exact duplicate of
an already-certified sibling — its `depends_on` names the sibling — do NOT
re-measure, re-derive, or re-judge it from scratch:

- The certified sibling is banked as a reusable component whose entry point
  draws the whole target INCLUDING shared chrome exactly once; dependents
  must never re-draw shared chrome.
- The duplicate's builder composes the component and applies ONLY the
  declared expected-delta (e.g. one badge numeral). Smoke-build the
  composition before spending a judge attempt.
- The judge prompt is the SAME frozen template as the sibling's, with the
  comparison clause IDENTICAL, and it DECLARES the expected relationship in
  its context channel: "expect an exact match to the <sibling> render except
  <declared delta list>". Facts travel in context, never template edits
  (references/judge-prompt-patterns.md).
- **Measurement reuse.** The duplicate inherits the sibling's measurements
  for everything outside the declared delta; fresh measurement is spent only
  on the delta region.
- **Adjudicated-artifact propagation.** Capture artifacts already adjudicated
  on the sibling (present in the original, excluded by ground rules) are
  excluded on the duplicate too — the propagation is recorded in the
  duplicate's context lines so the judge does not re-charge them.

**Derived (non-duplicate) dependents.** A dependent that is NOT a duplicate
still inherits shared structure: it composes from the sibling's per-block
exports plus its own measurements, and never re-derives shared chrome or
already-certified blocks.

A derived target's certification is provisional on its dependency: when the
dependency's bytes change, the cascade re-opens the dependent.

## Banked re-run discipline — prove reproduction before diagnosing

A confirmed FAIL row in a gate matrix is a claim about the target; its
reproducibility is a separate fact. (The per-call retry budget for failed
READS is verdict law; this is the per-ROW reproduction protocol.)

- **Never diagnose or fix from a single red.** Re-run the failing row from
  banked state (resume at the saved stage) and bank the attempt BEFORE any
  diagnosis or fix. Two independent reds with the same failure signature are
  the minimum to call a failure deterministic; one real gate banked on the
  order of ~19 full transcripts of a single failing row across its
  iterations before and while diagnosing it.
- **Every re-run banks a full transcript** under a fresh attempt name
  (`gate-run-<n>`, `gate-resume-<n>`, …) — never overwrite, never summarize
  in place. The bank IS the reproduction evidence.
- **Any green in the bank = flaky.** A row that is sometimes green does not
  take a code fix on the strength of a red: stop the fix path and
  investigate environment, race, or concurrency. A proven flake is its own
  defect of a different kind — an instability finding, charged as its own
  row.
- **Isolation runs for cheap iteration.** Once the row is proven
  deterministic, reproduce the failing unit in ISOLATION (dedicated diag
  runs outside the gate matrix) so diagnosis loops cheaply; the gate still
  owns the final verdict.
- **The fix's before/after claim cites the bank.** Fix verified = banked
  reds reproduced pre-fix, post-fix run(s) green, same row id, same gate
  version.

Gate and detector changes are proven able to fail before their greens are
trusted — the positive-control law lives in
references/evidence-discipline.md, as does the resume/checkpoint file
schema for a worker's own recovery points.
