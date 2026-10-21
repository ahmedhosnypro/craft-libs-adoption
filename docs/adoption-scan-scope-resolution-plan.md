# Amendment: anchor-bound crate naming and already-tracked routing — a delta on finding-accuracy-plan.md

**Status: proposal — saved, not implemented.**

**Relationship:** this document amends `docs/finding-accuracy-plan.md` ("planned, approved, not
started"). Every edit below extends that plan's steps rather than adding parallel ones, and it respects
commit `5be2a8b` ("stand solely on craft-libs scope policy, drop #94 extraction-map dependence"):
nothing materializes #94/#115 as a scope authority, and no run outcome depends on those issues being
fetchable. Upstream artifacts enter only as **live-resolved anchors** — the mechanism
finding-accuracy-plan's step 4b already requires.

> The previous draft of this document fetched #115/#94 into the scope-truth clone as the required
> naming authority and failed closed when the fetch failed. That reintroduced the map dependence the
> repo deliberately dropped and would have made every new-crate finding hostage to two issue fetches.
> It is withdrawn; the same correction is routed through anchor resolution instead. (Its Phase 1c
> snippet was also technically broken: `gh api .../comments --jq .body` errors on the comments array —
> `.[].body` is the correct filter.)

## What the accuracy plan still misses — the #16 walk

Run finding #16 (vectorcraft 1761, `impl Backend for Remote` — a *client* of a control channel) through
the accuracy plan:

1. It classifies in scope only after the watch-path fix (change 4 below); today vectorcraft's
   watch-paths omit `crates/mcp`, so the surface never reaches classification at all.
2. The step-4b crate-name gate **accepts `craft-mcp`**: "mcp" is not in the bucket list — it names a
   protocol — so the shape rule cannot catch the boundary error.
3. Anchor resolution then finds an open upstream issue covering the surface (#115) and reads it as a
   citation — but two checks never happen:
   - **Boundary wording.** The anchor's craft-control entry scopes this surface as "client reply
     validation with no automatic resend of mutations" — contradicting the directory-derived
     `craft-mcp`. Nothing notices.
   - **Prior citation.** The same entry **already cites vectorcraft 1761** (verified 2026-10-20 in
     #115's comments). Nothing routes the finding away from filing: the scan would add an issue whose
     only content upstream already has.

Those two checks are this amendment.

## Changes — all deltas on finding-accuracy-plan

### 1. `finding-filer.md` step 4b — two anchor checks (extends "Anchor resolution")

Keep the accuracy plan's step numbering exactly (4b between assets and diagram; steps 1–9 and every
cross-reference stay valid) and extend its anchor resolution with:

- **Boundary-wording check.** When the resolved primary anchor carries an entry whose scope line covers
  this finding's surface, the proposed `craft-<name>` must not contradict that entry's named target.
  On conflict, the anchor's wording wins: the proposal retargets and the issue's **Anchors** section
  names the conflict (source directory name → anchor name). A PR whose change genuinely spans both
  sides of a boundary goes back to the Phase 3 split rule, not into one issue.
- **Prior-citation check.** If the anchor's entry for this surface already cites one of the finding's
  evidence merges, the outcome is `already-tracked <slug> <anchor ref>` — **no issue is created**; the
  finding is recorded for the state body. Precise trigger: the anchor cites the merge, not merely
  "covers the surface" — an open upstream issue covering the surface but not carrying this evidence
  stays a primary anchor to *file against*.

Anchor reads are live, per finding, read-only (`gh api` GET only):

```
gh api repos/storytold/craft-libs/issues/115          --jq .body
gh api repos/storytold/craft-libs/issues/115/comments --paginate --jq '.[].body'
```

(8 comments today, one page; `--paginate` keeps it true if that grows. The boundary wording and the
1761 citation are both greppable in that output — verified 2026-10-20.)

### 2. Outcome vocabulary — one deliberate addition

`already-tracked <slug> <anchor ref>` joins the filer's outcome list (staged
`finding-filer.md:30-38`), the mission's Phase 3 filer template, and the orchestrator's verification.
The accuracy plan keeps the vocabulary otherwise unchanged; this is the only new word, and it files
nothing — consistent with the filer's write law (`gh issue create` / `gh issue edit` only).

Orchestrator verification replaces the withdrawn draft's grep into materialized map files: re-resolve
the cited anchor live and grep the quoted line from body + comments — the same "a child's claim is not
evidence" bar evidence already has.

### 3. `rollup-writer.md` — the sink for already-tracked

The candidate-pipeline `status` cell (staged `rollup-writer.md:61`) gains
`already-tracked: <anchor ref — merge now cited>`, and the window comment's **Goal movement** line
(~87) counts it. This sits beside the accuracy plan's `### Maintainer verdicts` section without
touching it: verdicts record maintainer decisions on the fork's findings; `already-tracked` records
upstream already carrying new evidence. Already-tracked rows keep their candidate row until a
maintainer acts; they are never silently dropped.

### 4. `config/repo-list.txt` — one watch-path

Add `crates/mcp` to vectorcraft's watch-paths. gridcraft (`crates/ui-egui,apps/gridcraft,crates/mcp,
crates/pdf`) and wordcraft (`...,crates/mcp,crates/render`) already watch theirs; vectorcraft is the
outlier, and without this the #16 surface is invisible to classification. No other watch-path changes —
the `candidates` column stays a hypothesis.

## Why this is enough

The staged rework fixed evidence discipline; the accuracy plan adds naming shape, boundary contracts,
anchor resolution, and the verdict loop. The #16 replay under the combined pipeline: in scope (change 4)
→ duplication proven in clones → name gate passes `craft-mcp` (accepted: the shape rule cannot see
boundaries) → anchor #115 resolves open → boundary check retargets to `craft-control` → prior-citation
check finds vectorcraft 1761 already cited → `already-tracked mcp-jsonrpc-robustness craft-libs#115`,
**zero new issues**, one state-body row. A genuine new-crate candidate with no anchor still files, with
`no dedicated upstream RFC` recorded and its name shaped by the step-4b gate. Upstream truth enters
per finding, live, only as anchors — no map dependence anywhere.

## Verification

1. **Anchor reads, for real, now (read-only):** the comments fetch with `--jq '.[].body'` returns the
   craft-control scope line and both vectorcraft-1761 citations (greppable — verified 2026-10-20).
2. **Structural:** the filer keeps steps 1–9 with 4b extended, no renumbering; exactly one new outcome
   word; the state-body change is one cell value plus its counting; the accuracy plan's own edits are
   untouched.
3. **Behavioral (CI — needs the model gateway; not runnable locally, no `craft-agent` binary):**
   dispatch one window and assert — the #16 replay returns `already-tracked`, zero new issues, the
   state row present; a no-anchor new-crate claim still files; a boundary conflict retargets and names
   the conflict in the Anchors section.
4. **Post-hoc on the fork:** the next ~5 findings carry an Anchors section whose quoted lines resolve
   live, or were already-tracked — no directory-name-derived crate names that contradict a resolvable
   anchor.
