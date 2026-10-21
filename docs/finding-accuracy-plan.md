# Plan: make adoption-scan findings accurate — close the gaps the staged rework left

Status: planned; revised; not started. Scope: pipeline files in `~/Projects/craft-libs-adoption`
only; no edits to already-open findings.

## Baseline — the staged, uncommitted rework (do not duplicate it)

The repo carries a staged rework (`git diff --cached`: new `source-cloner` agent,
`scripts/clone-sources.sh`, Phase 1b clone sweep, rewritten filer/classifier/rollup rules).
It already fixes most of what made findings #18/#25 inaccurate:

1. **Evidence is real code** — Phase 1b clones every scanned repo plus `storytold/craft-libs`
   (scope-truth) into `sources/`; classifiers judge patches, and packaging-only diffs
   (Cargo.toml features, xtask, docs) never clear the hoist bar alone.
2. **Duplication is proven or marked unverified** — per consumer: a real `sources/<app>/<path>`
   plus a PR or pin ref; a hoist may assert multi-app usefulness only with file evidence in two
   other apps; blanket sentences are deleted; `repo-list.txt`'s `candidates` column is a
   hypothesis, never evidence.
3. **Surface collision is checked** — step 2 reads `sources/craft-libs/crates/` and the issue
   body must carry a **Collision check** section (what craft-libs already covers).
4. **Asset/licensing gate** — non-source assets carry the craftrules `standards/licensing.md`
   precondition, recorded as a required **Preconditions** section.
5. **Dedupe** — exact-title match before filing (`already-filed`; no second issue).

## Remaining gaps (verified in the current files)

- **A. No crate-naming or scope-shape gate.** The filer records a "proposed crate name" with no
  check: a #18 clone would still file as one `craft-import` — a multi-family bucket name.
- **B. No boundary contract.** The body has no returns / apps-keep / not-in-scope section — the
  neutral-object contract upstream precedents carry (#57 `craft-svg`, #127 `craft-metafile`,
  #140 `craft-swatch`). Without it, crates drift toward renderer/document-model territory.
- **C. Anchors unenforced.** Mission Phase 3 requires citing "a merged craft-libs PR, or an open
  upstream issue", but the filer has no step resolving an anchor's state or fit — how #18 leaned
  on a closed map while skipping open RFC precedents. (Commit `5be2a8b` dropped #94-map
  dependence; that stands — no map anchors return.)
- **D. No maintainer-verdict loop.** The state body has no verdicts section and the promotion rule
  has no parked-candidate exemption, so a candidate closed with revival conditions (#17, closed
  2026-10-20: "accepted in principle; not adopted as proposed" + three conditions) is re-filable.
- **E. Mission/filer inconsistencies (pre-existing).** (i) Mission Phase 3 says an existing issue
  gets "a comment instead of a duplicate"; the filer's contract is `already-filed` with no
  comment, and its write law permits only `gh issue create` and `gh issue edit`. (ii) The filer
  shard prompt carries no proposed crate name, boundary, or anchor numbers — the child cannot
  verify what it was never given.

## Changes

### 1. `.craft-agent/agents/finding-filer.md` — scope-shape gate as step 4b

Insert **step 4b — Scope shape and anchors** between assets (step 4) and diagram drafting
(step 5), so refusals land before any diagram work. The letter is deliberate: existing step
numbers 1–9 and every internal cross-reference ("step 2", "step 4 fired", "step 6", "step 8",
"step 9") stay valid. Division of labor with step 2: step 2 answers *does craft-libs already
cover this surface*; 4b answers *is the crate name free and well-shaped, and are the anchors
real*.

- **Crate-name gate (hoist findings; port findings skip it — they extend an existing crate, so
  there is no new name to shape).** Resolve the proposed `craft-<name>` against the scope-truth
  clone: `sources/craft-libs/crates/` directory names (the `crates/<name>` → `craft-<name>`
  convention) and `sources/craft-libs/Cargo.toml` `craft-` dependency entries (watch-path
  addition in change 2; a degraded clone missing that file falls back to
  `gh api repos/storytold/craft-libs/contents/Cargo.toml`). Name already taken → the finding
  reframes as an extension of that crate (body and diagram name the existing crate), not a new
  one. Shape rule: the name must identify ONE format family or ONE role; bucket names (`import`,
  `io`, `doc`, `core`, `util`, `common`, `misc`) and multi-family payloads are
  `refused <slug> bad-crate-shape`. The filer does NOT split — it files at most ONE issue;
  splitting happens upstream in Phase 3 (change 2).
- **Boundary contract (hoist and port).** Required in the body: returns (neutral structures apps
  map into their own models), apps keep (document models, rendering, placement, UI), not in
  scope. Factual claims about code cite clone paths under a verified `sources/` clone;
  policy-level statements (what stays app-side) cite the scope policy instead — no cargo-cult
  path citations. A payload that needs a renderer or an editor document model to be useful is
  `refused <slug> policy-rejected` — the same reason word step 2 already uses.
- **Anchor resolution (hoist and port).** Anchors come from the shard (change 2) plus ONE
  bounded search: `gh issue list --repo storytold/craft-libs --state open --search '<surface
  keyword>' --limit 10` (read-only). Resolve every anchor candidate live (`gh issue view` /
  `gh pr view` on `storytold/craft-libs`) and record number + title + state in a required
  **Anchors** body section. Primary anchor: a merged craft-libs PR or an open upstream issue
  covering this surface; a closed artifact is a secondary citation, labeled `closed`, and is
  never the primary. No dedicated anchor → write `no dedicated upstream RFC` and name the
  closest open ones from the search.

Step 7's body contract gains the required sections **Boundary** and **Anchors** (alongside
Duplication evidence / Collision check / Preconditions). The outcome-line vocabulary is
unchanged — `bad-crate-shape` and `policy-rejected` are `refused` reasons, which already exist.

New hard rules, mirroring the existing duplication rule: a bucket/multi-family crate name does
not file; every cited anchor's resolved state appears in the Anchors section, and a closed
anchor is never presented as the primary anchor.

### 2. `missions/adopt-libs.md` + `.craft-agent/agents/lib-adoption-analyst.md` — split rule, shard contents, verdict loop, small fixes

- **Phase 3 filer template — shard contents (fixes E-ii).** Each filer item now carries the
  proposed crate name, a boundary sketch (one line per: returns / apps keep / not in scope), and
  any known upstream anchor numbers (from the pipeline row or verdict lines). The filer verifies
  these against the clones and live API — it never invents them. The self-contained-prompt law is
  preserved.
- **Phase 3 ranking — the split rule.** A hoist cluster spanning multiple format families
  composes ONE filer item per family/role, each with its own slug, crate name, boundary sketch
  and evidence slice; no filer is handed an unsplit multi-family payload (if one is, it refuses
  `bad-crate-shape`). Split items count against the existing ≤3 findings cap; over-cap splits
  stay deferred in the state body per the existing rule — the cap does not grow.
- **Phase 3 promotions — parked-candidate exemption.** Before promoting, the orchestrator reads
  the maintainer-verdict digest (below), slug-joined (candidate pipeline slug == the closed
  finding's `adoption-scan: <slug>` title). A candidate whose closed finding was parked with
  revival conditions is NOT re-filed unless a named condition is demonstrably met this window —
  then the promotion cites which condition. A candidate adopted or rejected outright is marked
  resolved in the pipeline, never re-filed.
- **`already-filed` evidence is not lost (completes E-i).** Harmonize the mission's "adds a
  comment instead of a duplicate" to the filer's actual contract (`already-filed`, no comment —
  the filer's write law permits only `gh issue create`/`gh issue edit`), and add: when a filer
  reports `already-filed`, the orchestrator records the new corroborating merges in the
  candidate's pipeline row via the state snapshot — new evidence reaches the issue through the
  human, not through new write shapes.
- **Run-start verdict digest.** Orchestrator, during the state read:
  `gh issue list --repo ahmedhosnypro/craft-libs --state closed --search 'adoption-scan in:title' --json number,title,closedAt`,
  then fetch each issue's comments and take the latest pre-closure comment carrying a
  Verdict/Resolution heading (no author check — only the maintainer writes those; none →
  `closed without recorded verdict`). Digest line per finding: number, slug, verdict, unmet
  conditions. It flows into the Phase 4 state snapshot.
- **Phase 1b scope-truth watch-paths** gain the root `Cargo.toml`:
  `AGENTS.md,Cargo.toml,crates,docs,licenses` — the name gate reads the real
  `[workspace.dependencies]` list from the clone instead of failing on a missing file.
  `source-cloner.md` itself needs no edit (watch-paths arrive in each clone item).
- **Analyst file.** Add the verdict-digest read and the promotion exemption to the "state is the
  goal's face" discipline.

### 3. `.craft-agent/agents/rollup-writer.md` — verdicts land in Mission State

Add a `### Maintainer verdicts` section to the state-body template (latest 5 closed findings:
`| #N | slug | verdict | unmet conditions |`), carry it forward at step 3, and let
candidate-pipeline rows for parked candidates reference the verdict row
(`parked — see verdicts #N`). Nothing else in the template changes.

## Out of scope

- The staged rework itself (clone sweep, duplication rules, collision check, classifier, budgets,
  spawn shapes, write law — all correct and load-bearing).
- #94-style map anchors (stay dropped per commit `5be2a8b`).
- Edits to already-open findings (user chose pipeline-only).
- `config/repo-list.txt` and `source-cloner.md` (no change needed — scope-truth watch-paths live
  in the mission text and reach the cloner via its item).

## Verification

Items 1–4 run as plain `gh`/`grep` — no model run. Item 5 observes the next scheduled run.

1. **Name-gate inputs**: `gh api repos/ahmedhosnypro/craft-libs/contents/crates --jq '.[].name'`
   (11 current crates) and the root Cargo.toml `craft-` entries; confirm the shape rule rejects
   `craft-import` (bucket + multi-family) and accepts a format-family name, and that a taken
   name (e.g. `craft-pdf`) reframes to an extension rather than a duplicate-crate proposal.
2. **Boundary claims are checkable**: factual claims in a Boundary section cite paths under a
   verified `sources/` clone; policy-level statements cite the scope policy.
3. **Anchor resolution both directions**: `gh issue view 57 --repo storytold/craft-libs --json
   state,title` (open RFC → eligible primary) vs `gh issue view 94` (closed → secondary, labeled
   `closed`, never primary).
4. **Verdict digest is collectable**: `gh issue list --repo ahmedhosnypro/craft-libs --state
   closed --search 'adoption-scan' --json number,title` plus #17's Resolution comment parses to
   (slug, verdict, unmet conditions) under the latest-Resolution-heading rule.
5. **End-to-end**, on the next scheduled window (a manual dispatch is optional — a run writes
   real issues on the fork): the next filed finding carries the Duplication, Collision,
   **Boundary** and **Anchors** sections and a non-bucket crate name; a #18-clone is split per
   family at Phase 3 or refused `bad-crate-shape`; a parked candidate is not re-filed; the state
   body shows the verdict digest.
