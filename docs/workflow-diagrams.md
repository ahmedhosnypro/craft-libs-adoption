# The adoption scan, visualized

How the six-hour craft-libs adoption scan actually runs: the GitHub Actions job in
`.github/workflows/adopt-libs.yml`, the mission phases from `missions/adopt-libs.md`, and the
subagent pool of `.craft-agent/agents/`. Every name below is a real file, step, phase, agent, or
artifact. One diagram per concept; nothing here invents entities.

Two modes are drawn here. **Mission mode** (sections 1–9) is today's CI default and the rollback
path: `lib-adoption-analyst` drives the phases itself and the specialists write to GitHub directly.
**Workflow mode** (sections 10–12) is the judged DAG in `.craft-agent/workflows/adopt-libs.md` —
8 steps gating every GitHub write behind a panel and an appellate verdict, and running each PR's
whole life on its own detached pipeline. Mission mode is the
current reality; workflow mode is what the same run becomes, so where the two conflict the
mission-mode sections describe the rollback path, not the destination.

## 1. The CI job — boot the gateway, run the scan

The job `scan` on `ubuntu-latest` (timeout 360 min). The private model gateway comes from the
published IronRouter release (`ahmedhosnypro/IronRouter`): the latest release (or a dispatch-pinned
`gateway-tag`) is downloaded and checksum-verified, the registry dump is fetched from the backend
source repo (`ahmedhosnypro/ironrouter-backend`) by itself, restored into Postgres on :5434, and
the gateway binary serves on :17844 before `scripts/run-scan.sh` starts the agent. The pulse step is
best-effort: it never turns a green scan red.

Mission mode (the rollback path): the `Load the mission prompt` step reads
`missions/adopt-libs.md`, and `scripts/run-scan.sh` runs `craft-agent run --agent
lib-adoption-analyst --prompt <mission file>`. Workflow mode swaps that for `craft-agent workflow
--workflow adopt-libs` (no `--max-tokens` — it is a per-step cap), with the renderer following the
run's journal (step events) and the per-step session transcripts (prompts, tool calls, tool results)
under `.craft-agent/workflows/<run_id>/` for mid-step liveness; `run-scan.sh` selects it from
`CRAFT_AGENT_WORKFLOW`, which the `workflow` dispatch dropdown sets (`mission` or `adopt-libs`);
scheduled cron runs always take the workflow, a dispatch with the input left at `mission` keeps the
mission — see section 10. Concurrency is event-scoped:
scheduled runs serialize on one group (`adopt-libs-scheduled`), and every manual dispatch joins its own
group (`adopt-libs-${{ github.run_id }}`), so a mission scan and a workflow rehearsal can run at the
same time — the tracking-issue state update and the `already-filed`/`already-open` checks are the
racy surfaces those parallel runs share.

```mermaid
flowchart TD
    Trigger["cron 20 0,6,12,18 * * *<br/>or workflow_dispatch"] --> Checkout["Check out the repository"]
    Checkout --> FetchGW["Download the model gateway release<br/>ahmedhosnypro/IronRouter, checksums verified"]
    FetchGW --> FetchDump["Fetch the registry dump<br/>ironrouter-backend/ironrouter-registry.dump via contents API"]
    FetchDump --> Postgres["Start the gateway database<br/>postgres:17 on :5434"]
    Postgres --> Restore["Restore the model registry<br/>pg_restore ironrouter-registry.dump"]
    Restore --> Migrate["Apply pending gateway migrations<br/>ironrouter-migration-x86_64-unknown-linux-gnu up"]
    Migrate --> StartGW["Start the model gateway<br/>ironrouter-x86_64-unknown-linux-gnu on :17844"]
    StartGW --> WaitGW["Wait for the gateway<br/>/healthz then /v1/models"]
    WaitGW --> Mission["Load the mission prompt<br/>missions/adopt-libs.md"]
    Mission --> RunScan["Run the adoption scan<br/>scripts/run-scan.sh, craft-agent run --agent lib-adoption-analyst"]
    RunScan --> Transcript["Upload the run transcript<br/>run-transcript artifact"]
    Transcript --> Pulse["Keep the schedule alive<br/>scan pulse into .scan-log"]
```

## 2. The mission phases

**Mission mode — the rollback path.** The orchestrator `lib-adoption-analyst` computes the window
itself (`date -u -d '7 hours ago'` — a 7-hour look-back on the 6-hour cadence), reads the tracking
issue's Mission State body and the maintainer-verdict digest, then drives the phases. Zero
merges skips classification; the clones still run because duplication is proven across the suite,
not across the window. Phase 1, Phase 1b, and the digest read are scripts started by
`scripts/launch-sweeps.sh` in one call, running concurrently — the AI never collects or clones.

Under the judged workflow (section 10) the same phases become steps: `prepare` launches and verifies
the sweeps, `pr-pipeline` dispatches one pipeline per PR that runs Phases 2–4 inside itself, and
the specialists' writes sit behind the pipeline's lease and the gates.

```mermaid
flowchart TD
    Init["Run start: window, Mission State,<br/>maintainer-verdict digest, mission.db"] --> Sweep["scripts/launch-sweeps.sh — ONE call<br/>collection + clone sweep + digest read, concurrent"]
    Sweep --> Zero{"Any merges in window?"}
    Zero -->|Yes| P2["Phase 2 — Classify<br/>one DETACHED child per PR, every group in one turn"]
    P2 --> Poll["poll_agents as each verdict lands —<br/>that PR advances to its stage-2 child immediately"]
    Poll --> P3["Phase 3 — File findings + pin bumps<br/>≤3 findings, ≤3 bumps, per PR as it advances"]
    Zero -->|No| P3
    P3 --> Stop{"Turn 180 stop rule"}
    Stop --> P4["Phase 4 — Deliver<br/>rollup-writer spawn_agent"]
    P4 --> Body["Mission State body<br/>on tracking issue Adoption scan rollups"]
    P4 --> Comment["Window comment<br/>3–8 lines + one Signal line per active repo"]
```

## 3. The run as a sequence

The orchestrator never classifies, files, or delivers itself; the sweep is a script, every PR is its
own detached child, and each PR advances to its stage-2 child the moment its verdict is verified —
no wave barrier between PRs, and no PR waiting on another.

**Rollback-path note:** the arrows below are mission mode. Under the judged workflow the same
children are stage children of the PR's own pipeline, each write gated by a filing lease and then by
the pipeline-gate; see section 12.

```mermaid
sequenceDiagram
    participant O as lib-adoption-analyst
    participant S as scripts/launch-sweeps.sh
    participant M as merge-classifier
    participant F as finding-filer
    participant A as revsync-applier
    participant R as rollup-writer
    O->>O: Compute window, read Mission State, build verdict digest
    O->>S: launch — collection, clone sweep, digest (concurrent)
    S-->>O: rows.jsonl, clone-outcomes.txt, digest.md
    O->>M: spawn_agents DETACHED — one item per PR, all groups in one turn
    M-->>O: accepted ids (immediate, no await)
    O->>O: poll_agents waitSecs 120 — collect as verdicts land
    M-->>O: pr-<number>.verdict line per PR
    O->>F: spawn_agent for THIS PR's hoist/port verdict (detached)
    O->>A: spawn_agent for THIS PR's rev-sync verdict (detached)
    F-->>O: issue filed as adoption-scan: <slug>
    A-->>O: pin-bump PR or recorded blocker
    O->>R: spawn_agent — composed state snapshot
    R-->>O: Mission State body + window comment verified
```

## 4. The subagent tree

Depth 2 by design and never deeper: the orchestrator spawns per-PR pipeline children, and each
pipeline spawns its own stage children, which spawn nothing. Every spawn carries `maxTurns: 10000`
and a finite `timeoutSecs` (1800, or 3600 for a classifier child) and omits `maxTokens`: subagent
token budgets are unlimited and reserve nothing, so a group's admission never depends on a
slice-times-count reservation.

```mermaid
flowchart LR
    O["lib-adoption-analyst<br/>depth 0"] --> PL["pr-pipeline<br/>depth 1, ONE per PR — spawns its own stages"]
    PL --> M["merge-classifier<br/>depth 2, ONE per PR — never spawns"]
    PL --> F["finding-filer<br/>depth 2, detached per advancing PR"]
    PL --> A["revsync-applier<br/>depth 2, detached per advancing PR"]
    PL --> C["finding-committer /<br/>revsync-committer<br/>depth 2, after a filing lease"]
    O -.->|"judged workflow only"| RS["rollup-writer ×1<br/>depth 1, spawn_agent from rollup-seal"]
```

## 5. Inside one classification pipeline

A classifier child owns exactly ONE PR — no coordinator, no grandchild, because a coordinator is a
barrier its members wait on and a grandchild adds a level the per-PR shape does not need. Its moves
— claim, fetch, classify, verify — describe the fastest honest path; turn counts are guidance, not
caps. Every child in the wave is independent: it shares nothing with any other child and waits on
none.

```mermaid
sequenceDiagram
    participant Kid as merge-classifier (one PR)
    participant Ledger as run-ledger/classifier/pr-<number>/
    participant API as GitHub REST API
    participant Clone as sources/<repo>/ (Phase 1b)
    Kid->>Ledger: scope-claim pr-<number>
    Kid->>API: GET changed-file list (paginate, per_page=100)
    Kid->>API: GET patch/diff for watch-path files only
    Kid->>Clone: suite context for duplication (never the PR's evidence)
    Kid->>Ledger: task row + pr-<number>.verdict
    Kid-->>Kid: verdict line as the final message
```

## 6. A PR's verdict lifecycle

Verdict classes come from `missions/adopt-libs.md`: `rev-sync`, `hoist`, `port`, `irrelevant`,
`unverified`, or `maturing:<slug>`. A maturing candidate reaches filing only after corroboration in
two consecutive windows, and only when the maintainer-verdict digest's revival conditions allow it.

```mermaid
stateDiagram-v2
    [*] --> Collected: merged_at >= window start
    Collected --> Dispatched: one DETACHED child per PR, newest-first
    Dispatched --> Fetched: changed-file list + patch
    Fetched --> Irrelevant: no watch-path intersect<br/>pin files always in scope
    Fetched --> Unverified: patch missing or truncated
    Fetched --> RevSync: craft-libs pin bump, old/new rev
    Fetched --> Hoist: generic src/ logic, packaging rule passed
    Fetched --> Port: source-archetype contract ripples to apps
    Fetched --> Maturing: weak generic signal, share stated
    RevSync --> PinBumpPR: revsync-applier
    PinBumpPR --> [*]
    Hoist --> FindingIssue: finding-filer
    Port --> FindingIssue
    FindingIssue --> [*]
    Maturing --> Pipeline: candidate pipeline, streak n
    Pipeline --> [*]
    Irrelevant --> [*]
    Unverified --> Exception: window comment
    Exception --> [*]
```

## 7. The filer's gate chain

**Rollback-path note:** this chain ends with `File adoption-scan: <slug>` because in mission mode
the filer writes to GitHub itself. Under the judged workflow the chain stops at the draft in
`run-ledger/filer/<slug>/` and `file-commit` (`finding-committer`) performs the only write — see
section 12.

A finding only reaches GitHub after the scope-truth clone is read, the crate shape passes, and
duplication is proven per consumer. A hoist carries exactly one validated mermaid diagram or it
does not file at all.

```mermaid
flowchart TD
    Item["Hoist or port shard<br/>crate name, boundary sketch, anchors"] --> Scope["Read sources/craft-libs/<br/>AGENTS.md, crates/, Cargo.toml"]
    Scope --> ScopeOk{"Scope-truth clone verified?"}
    ScopeOk -->|No| Defer["Defer filing, report exception"]
    ScopeOk -->|Yes| Skill["Read mermaid-diagrams skill"]
    Skill --> Gate{"Crate-shape gate:<br/>one family or one role?"}
    Gate -->|No| Refuse["bad-crate-shape<br/>refuse item"]
    Gate -->|Yes| Boundary["Write Boundary:<br/>returns / apps keep / not in scope"]
    Boundary --> Dupe["Verify duplication per consumer<br/>sources/<app>/<path> + PR or pin ref"]
    Dupe --> AllOk{"Every consumer proven?"}
    AllOk -->|No| Unverified["Mark consumer unverified"]
    AllOk -->|Yes| License{"Non-source asset move?"}
    License -->|Yes| Pre["Licensing precondition"]
    License -->|No| Anchors["Resolve anchors live<br/>number + title + state"]
    Pre --> Anchors
    Anchors --> Diagram["Build and validate the ONE mermaid diagram"]
    Diagram --> File["File adoption-scan: <slug><br/>on ahmedhosnypro/craft-libs"]
    Defer --> Report["Report in window comment"]
    Unverified --> File
```

## 8. The cadence and the look-back

Four windows a day. The 7-hour look-back overlaps the 6-hour cadence by an hour — idempotent,
because merges are keyed by `owner/repo#number` — and it heals a missed slot.

```mermaid
timeline
    title Six-hour cadence, cron 20 0,6,12,18 * * *
    section Daily windows
        Window 1 : 00:20 UTC scan, looks back to 17:20 UTC previous day
        Window 2 : 06:20 UTC scan, looks back to 23:20 UTC
        Window 3 : 12:20 UTC scan, looks back to 05:20 UTC
        Window 4 : 18:20 UTC scan, looks back to 11:20 UTC
```

## 9. The subagent budget

At most 4096 subagents per run, and at most 48 concurrent tree-wide (the scan's knob is a
deliberate bound, not a ceiling: each child is a full runner with its own context and provider
stream, and the job's runner has 7 GB). A saturated pool queues detached spawns rather than
refusing them, and a dispatch from a running pipeline launches ahead of fresh dispatches, so every
PR's next stage runs the moment a slot frees. Token budgets stay unlimited (only the run's own
budget guards); every spawn carries a finite wall clock.

**Rollback-path note:** this pie is mission mode's pool. Under the judged workflow the engine
sequences the 8 steps itself (`max-concurrent-steps: "4"`) and `pr-pipeline` dispatches its detached
per-PR pool, bounded by the same 4096-per-run cap and the run's `max-total-turns: "10000"`.

```mermaid
pie showData title Subagents within the 4096-per-run cap
    "Per-PR classifier children (detached pool)" : 228
    "Filers + appliers" : 6
    "Rollup child + retry reserve" : 22
```

---

## 10. The judged workflow — the 8-step DAG, one pipeline per PR

Workflow mode lives in `.craft-agent/workflows/adopt-libs.md` (frontmatter `name: adopt-libs`, arg
`window` default `7h`) — the same scan, but the engine sequences the steps instead of the
orchestrator, and every GitHub write sits behind a verdict. Limits: `max-steps: "10"`,
`max-concurrent-steps: "4"`, `max-total-turns: "10000"`, `max-total-tokens: "1000000000"`,
`max-retries-per-step: "2"`. Every step states `max-turns`, `retry`, and `on-failure` explicitly —
never relying on the 25/0/stop defaults. The judge seats are budget-bound, not advised: the gate
bodies write a call plan (call 1 one composed bash pass, 2-4 the live reads) and the step caps bind
it — `max-turns: "90"` on the panel gates, `"60"` on the appeals — so a seat that walks the ledger
file-by-file fails instead of spending the window.

The shape: a scripted parallel sweep (`prepare`), one per-PR dispatch step (`pr-pipeline`), one
merged judge family (`pipeline-gate`, `pipeline-appeal`), and the seal island (`rollup-seal`,
`rollup-gate`, `rollup-appeal`, `rollup-commit`) that starts the moment `pr-pipeline` settles and
waits for both appeals before its single write. Only success releases dependants, so what happens
after a failure depends on that step's `on-failure`.

What changed from the 10-step shape and why: the write lanes collapsed INTO the pipelines. A PR's
whole life — classification, filing, and its own rollup section — now runs inside one detached
`pr-pipeline` child, so `file-commit`/`bump-commit`/`rollup-draft` are no longer steps: the
commsitters and the rollup-writer are stage children the pipeline itself spawns. The step's job
shrank to dispatching the window's pipelines, polling only its own ids, verifying their
deliverables, and naming exceptions. The gates stayed: one judge family audits the whole per-PR
output — every PR has a row, the filing leases honored the ≤3/≤3 caps, the filed issues and opened
PRs match their verified drafts — and the seal is one single-writer commit.

**Failure policy — schema-enforced, not a preference.** A step the run survives a failure of
(`skip` or `warn`) must be a leaf: the workflow schema forbids `skip`/`warn` on a step that has
dependants, or the pipeline stalls. So every step anything depends on is `stop`, and only
`rollup-commit` — nothing needs it — is `skip`. A gate that settles failed therefore halts
admissions: the run ends `Failed` (exit 1 on a step error, 2 on max-turns, 3 on budget), its
dependants settle as skipped with a named `DependencyFailed` reason (journaled, never silent), and
the next run heals from the prior state body.

`rollup-seal` composes the state snapshot from the pipelines' per-PR sections under
`run-ledger/rollup/<slug>.md`, the outcome rows, and the journal — a missing section is a named
exception, never a guess — with a bounded wait (≤45 min) for the file and bump lanes. `pr-pipeline`
carries the heaviest budget (1200 turns): one detached child per PR, then polls as each pipeline's
envelope lands and verifies its ledger, verdict file, packages, and outcome rows.

```mermaid
flowchart TD
    P["1 prepare — lib-adoption-analyst<br/>scripts/launch-sweeps.sh: collection, clone sweep,<br/>verdict-digest read — all concurrent"] --> Q["2 pr-pipeline — lib-adoption-analyst<br/>one DETACHED pr-pipeline child per PR;<br/>each child owns that PR's whole life"]
    Q --> PG{"3 pipeline-gate<br/>verdict-judge, panel 3, majority"}
    PG -->|pass| PA{"4 pipeline-appeal<br/>appellate-judge, panel 1, unanimous"}

    subgraph seal["seal island — steps 5-8"]
        direction TB
        RS["5 rollup-seal — lib-adoption-analyst<br/>compose per-PR sections + outcomes"] --> RG{"6 rollup-gate<br/>verdict-judge, panel 3, majority"}
        RG -->|pass| RA{"7 rollup-appeal<br/>appellate-judge, panel 1, unanimous"}
        RA -->|uphold| RC["8 rollup-commit — rollup-committer<br/>needs BOTH appeals"]
        RG -.->|"fail: gate stops the run (skips below it, named)"| RC
    end

    Q -->|"needs: pr-pipeline only"| RS
    PA -->|"uphold: the seal may post"| RC
    PG -.->|"fail: run stops; the seal settles skipped (DependencyFailed)"| RC
```

The dotted edges show what a failed gate does: admissions halt, and everything below it settles as
skipped with a named `DependencyFailed` reason — the seal never posts, and the run's conclusion is
`Failed` with the journal carrying every reason.

## 11. One pipeline — per PR, a whole life, never blocked by a sibling

`pr-pipeline` is the step the per-PR architecture lives in. It shards `rows.jsonl` into ONE item per
PR and dispatches the whole window as detached `pr-pipeline` children: every group's `spawn_agents`
call carries `"detached": true`, so it returns at admission and the pool runs the members under the
concurrency knob. Each child then runs its PR's ENTIRE life inside itself, spawning its own stage
children detached and polling only its own ids. A PR may finish its whole life — classification,
filed issue, rollup section — while another PR is still in its first stage.

The pool makes that true at window scale. A saturated pool QUEUES a detached spawn instead of
refusing it (the caller already returned at admission), and a dispatch from a running child — a
continuation — launches ahead of fresh dispatches the root parent has not started, so a PR's next
stage never waits behind pipelines that have not begun. Every parent polls ONLY the ids its own
spawn calls named: the hub is shared, and a bulk drain would steal a sibling's envelope.

```mermaid
sequenceDiagram
    participant O as pr-pipeline (orchestrator)
    participant Pool as subagent pool (cap 48)
    participant A as PR #41 pipeline (rev-sync)
    participant B as PR #900 pipeline (hoist)
    participant C as PR #1200 pipeline (irrelevant)

    O->>Pool: spawn_agents pr-pipeline detached, groups of 2..32, one turn
    Pool-->>O: accepted ids (immediate — no await)
    O->>O: poll_agents by explicit ids, waitSecs 120
    A->>Pool: spawn_agent merge-classifier for #41 (detached, continuation)
    B->>Pool: spawn_agent merge-classifier for #900 (detached, continuation)
    C->>Pool: spawn_agent merge-classifier for #1200 (detached, continuation)
    Pool->>C: fetch files, no watch-path hit
    C-->>Pool: verdict: irrelevant
    C->>C: rollup section + ledger row — journey ends
    Pool-->>O: poll collects #1200 → verified, done
    Pool->>A: fetch files, Cargo.lock pin bump
    A-->>Pool: verdict: rev-sync
    A->>Pool: scripts/filing-lease.sh bump <slug> — leased
    A->>Pool: spawn_agent revsync-applier (detached) → revsync-committer (detached)
    Note over A,B: #41 is filed and finished while #900 is<br/>still in its FIRST stage — by design
    Pool->>B: fetch files, generic logic in src/
    B-->>Pool: verdict: hoist
    B->>Pool: scripts/filing-lease.sh finding <slug> — leased
    B->>Pool: spawn_agent finding-filer (detached) → finding-committer (detached)
    B->>B: rollup section + ledger row — journey ends
```

What the shape buys, and what it costs. Bought: a PR's whole life never waits on a sibling; the
wall-clock reclaims one child without stalling 47 others; each pipeline's context holds one PR's
journey instead of a window's; the filing lease keeps the ≤3/≤3 caps honest without a ranking
barrier. Cost: each pipeline tracks its own stage children, which is why per-PR state lives in
`run-ledger/pipeline/` and a pipeline's context holds only its own chart — it verifies a stage
child by reading its FILE, never by re-reading the envelope into its own context.

## 12. The pipeline's own writes — leased, then committed

The stage-2 drafters and the committers are different agents, and they are all stage children of
the pipeline that owns the PR. `finding-filer` writes `run-ledger/filer/<slug>/draft.md` plus its
evidence bundle and returns `ready <slug>` / `already-filed` / `already-tracked` / `refused` /
`blocked`; `revsync-applier` clones, branches, and commits pin lines locally — never pushes —
writing `run-ledger/revsync/<slug>/branch.md` and the PR body and returning `ready` /
`already-open #N` / `blocker`. BEFORE any committer runs, the pipeline takes its lease from
`scripts/filing-lease.sh` — `flock`-guarded, at most 3 findings and 3 bumps per window — and an
over-cap PR defers with its reason recorded. Only then do the committers perform the writes, each
idempotently so a retry can never duplicate an issue; the judges re-verify the result live
afterward.

```mermaid
flowchart LR
    subgraph pipeline["one pr-pipeline child (depth 1)"]
        direction TB
        CL["merge-classifier<br/>pr-<number>.verdict"] --> |"rev-sync / hoist / port"| DR{"stage-2 drafter<br/>detached, continuation-priority"}
        DR --> |"over-cap: defer"| DEF["deferred —named in the rollup section"]
        LEASE["scripts/filing-lease.sh<br/>flock, ≤3 findings, ≤3 bumps"] --> |"leased"| COMM["finding-committer /<br/>revsync-committer"]
        DR --> |"package verified"| LEASE
    end
    COMM --> W["the lane's only GitHub writes:<br/>finding issue on craft-libs,<br/>pin-bump PR on the app repo"]
    COMM --> OUT["run-ledger/outcomes/<br/>file-<slug>.md, bump-<slug>.md"]
    CL --> SEC["run-ledger/rollup/<slug>.md<br/>this PR's own section"]
    COMM --> SEC
```
