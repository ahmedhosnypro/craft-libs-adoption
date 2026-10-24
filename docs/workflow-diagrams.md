# The adoption scan, visualized

How the six-hour craft-libs adoption scan actually runs: the GitHub Actions job in
`.github/workflows/adopt-libs.yml`, the mission phases from `missions/adopt-libs.md`, and the
subagent pool of `.craft-agent/agents/`. Every name below is a real file, step, phase, agent, or
artifact. One diagram per concept; nothing here invents entities.

Two modes are drawn here. **Mission mode** (sections 1–9) is today's CI default and the rollback
path: `lib-adoption-analyst` drives the phases itself and the specialists write to GitHub directly.
**Workflow mode** (sections 10–12) is the judged DAG in `.craft-agent/workflows/adopt-libs.md` —
10 steps gating every GitHub write behind a panel and an appellate verdict, and running one pipeline
per PR. Mission mode is the
current reality; workflow mode is what the same run becomes, so where the two conflict the
mission-mode sections describe the rollback path, not the destination.

## 1. The CI job — boot the gateway, run the scan

The job `scan` on `ubuntu-latest` (timeout 360 min). The private model gateway comes from the
published IronRouter release (`ahmedhosnypro/IronRouter`): the latest release (or a dispatch-pinned
`gateway-tag`) is downloaded and checksum-verified, the registry dump is fetched from the backend
source repo (`ahmedhosnypro/ironrouter-backend`) by itself, restored into Postgres on :5434, and
the gateway binary serves on :17844 before `scripts/run-scan.sh` starts the agent. The pulse step is
best-effort: it never turns a green scan red.

Mission mode (the current default and the rollback path): the `Load the mission prompt` step reads
`missions/adopt-libs.md`, and `scripts/run-scan.sh` runs `craft-agent run --agent
lib-adoption-analyst --prompt <mission file>`. Workflow mode swaps that for `craft-agent workflow
--workflow adopt-libs` (no `--max-tokens` — it is a per-step cap), with the renderer following the
run's journal (step events) and the per-step session transcripts (prompts, tool calls, tool results)
under `.craft-agent/workflows/<run_id>/` for mid-step liveness; `run-scan.sh` selects it from
`CRAFT_AGENT_WORKFLOW`, which the `workflow` dispatch dropdown sets (`mission` or `adopt-libs`);
scheduled runs always take the mission — see section 10. Concurrency is event-scoped:
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
the sweeps, `pr-pipeline` runs Phase 2 as one pipeline per PR, and the specialists no longer write to
GitHub at all.

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

**Rollback-path note:** the arrows below are mission mode. Under the judged workflow the filer,
applier, and rollup children only produce drafts in `run-ledger/`; the writes shown here move to
the committers behind the gates of section 11.

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

Depth 2 by design and never deeper: the orchestrator spawns children, and a per-PR child never
spawns — the coordinator layer is gone. Every spawn carries `maxTurns: 10000` and a finite
`timeoutSecs` (1800, or 3600 for a classifier child) and omits `maxTokens`: subagent token budgets
are unlimited and reserve nothing, so a group's admission never depends on a slice-times-count
reservation.

```mermaid
flowchart LR
    O["lib-adoption-analyst<br/>depth 0"] --> M["merge-classifier<br/>depth 1, ONE per PR — never spawns"]
    O --> F["finding-filer ×≤3<br/>depth 1, detached per advancing PR"]
    O --> A["revsync-applier ×≤3<br/>depth 1, detached per advancing PR"]
    O --> R["rollup-writer ×1<br/>depth 1, spawn_agent"]
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

At most 1024 subagents per run, and at most 48 concurrent tree-wide (the scan's knob is a
deliberate bound, not a ceiling: each child is a full runner with its own context and provider
stream, and the job's runner has 7 GB — the hub queues the rest FIFO, so the window's per-PR
pipelines still all progress, just 48 at a time). The reserve covers the stage-2 filers and
appliers, the rollup child, and retries; the rest is per-PR classifier children, and their token
budgets are unlimited (only the run's own budget guards). Beyond the cap the run classifies
newest-first and reports the unclassified count as an exception.

**Rollback-path note:** this pie is mission mode's pool. Under the judged workflow the engine
sequences the 10 steps itself (`max-concurrent-steps: "4"`) and `pr-pipeline` dispatches its
detached per-PR pool, bounded instead by the run's `max-total-turns: "10000"` and
`max-total-tokens: "100000000"` pool.

```mermaid
pie showData title Subagents within the 1024-per-run cap
    "Per-PR classifier children (detached pool)" : 228
    "Filers + appliers" : 6
    "Rollup child + retry reserve" : 22
```

---

## 10. The judged workflow — the 10-step DAG, one pipeline per PR

Workflow mode lives in `.craft-agent/workflows/adopt-libs.md` (frontmatter `name: adopt-libs`, arg
`window` default `7h`) — the same scan, but the engine sequences the steps instead of the
orchestrator, and every GitHub write sits behind a verdict. Limits: `max-steps: "12"`,
`max-concurrent-steps: "4"`, `max-total-turns: "10000"`, `max-total-tokens: "100000000"`,
`max-retries-per-step: "2"`. Every step states `max-turns`, `retry`, and `on-failure` explicitly —
never relying on the 25/0/stop defaults.

The shape: a scripted parallel sweep (`prepare`), one per-PR pipeline step (`pr-pipeline`), one
merged judge family (`pipeline-gate`, `pipeline-appeal`), two committers that need only the appeal
(`file-commit`, `bump-commit`), and the rollup island (`rollup-draft`, `rollup-gate`,
`rollup-appeal`, `rollup-commit`) that starts the moment `prepare` settles. Only success releases
dependants, so what happens after a failure depends on that step's `on-failure`.

What changed from the 16-step shape and why: `classify`, `file-draft`, and `bump-draft` collapsed
into `pr-pipeline` because a per-PR pipeline is not a phase — every PR's journey is its own, and a
PR may finish while another is only in its first stage. The gates merged for the same reason: one
judge family verifies the whole per-PR output, exhaustive only on the ≤3 findings and ≤3 bumps that
can actually be filed, sampled elsewhere.

**Failure policy — schema-enforced, not a preference.** A step the run survives a failure of
(`skip` or `warn`) must be a leaf: the workflow schema forbids `skip`/`warn` on a step that has
dependants, or the pipeline stalls. So every step anything depends on is `stop`, and only the three
leaf committers — nothing needs them — are `skip`. A gate that settles failed therefore halts
admissions: the run ends `Failed` (exit 1 on a step error, 2 on max-turns, 3 on budget), its
committers settle as skipped with a named `DependencyFailed` reason (journaled, never silent), and
the next run heals from the prior state body. A skipped *committer* still records the failure (the
run is `Failed`), but in-flight sibling branches keep running, so their terminal rows reach the
rollup's exception list — that is the audit trail for a failed lane.

`rollup-draft` composes the snapshot from the terminal `run-ledger/outcomes/*.md` rows and the
journal — skipped steps become named exceptions, never silence — with a bounded wait (≤45 min) for
the file and bump lanes, and never claims an artifact it cannot verify. `pr-pipeline` carries the
heaviest budget (1200 turns): one detached child per PR, then polls as each verdict lands and
advances that PR immediately, so a `rev-sync` PR gets its applier while a `hoist` PR three hundred
rows down is still fetching files.

```mermaid
flowchart TD
    P["1 prepare — lib-adoption-analyst<br/>scripts/launch-sweeps.sh: collection, clone sweep,<br/>verdict-digest read — all concurrent"] --> Q["2 pr-pipeline — lib-adoption-analyst<br/>one DETACHED child per PR; poll_agents as each verdict lands;<br/>that PR advances to its stage-2 child immediately"]
    Q --> PG{"3 pipeline-gate<br/>verdict-judge, panel 3, majority"}
    PG -->|pass| PA{"4 pipeline-appeal<br/>appellate-judge, panel 1, unanimous"}

    subgraph writes["write lanes — need only the appeal"]
        direction TB
        FC["5 file-commit — finding-committer"]
        BC["6 bump-commit — revsync-committer"]
    end

    subgraph rollup["rollup island — steps 7-10"]
        direction TB
        RD["7 rollup-draft — lib-adoption-analyst"] --> RG{"8 rollup-gate<br/>verdict-judge, panel 3, majority"}
        RG -->|pass| RA{"9 rollup-appeal<br/>appellate-judge, panel 1, unanimous"}
        RA -->|uphold| RC["10 rollup-commit — rollup-committer"]
        RG -.->|"fail: gate stops the run (skips below it, named)"| RC
    end

    P -->|"needs: prepare only"| RD
    PA -->|uphold| FC
    PA -->|uphold| BC
    PG -.->|"fail: run stops; both write lanes settle skipped (DependencyFailed)"| FC
```

The dotted edge shows what a failed gate does: admissions halt, and everything below it settles as
skipped with a named `DependencyFailed` reason — the committers never run, the rollup island
finishes if already in flight, and the run's conclusion is `Failed` with the journal carrying every
reason.

## 11. One pipeline — per PR, detached, never blocked by a wave

`pr-pipeline` is the step the per-PR architecture lives in. It shards `rows.jsonl` into ONE item per
PR and dispatches the whole window as detached children: every group's `spawn_agents` call carries
`"detached": true`, so it returns at admission and the pool runs the members under the concurrency
knob while the orchestrator does other work. No call awaits a wave, so no PR waits for another.

```mermaid
sequenceDiagram
    participant O as pr-pipeline (orchestrator)
    participant Pool as subagent pool (cap 48)
    participant A as PR #41 (rev-sync)
    participant B as PR #900 (hoist)
    participant C as PR #1200 (irrelevant)

    O->>Pool: spawn_agents merge-classifier detached, 22 groups of 32
    Pool-->>O: accepted ids (immediate — no await)
    O->>O: poll_agents waitSecs 120
    Pool->>C: fetch files, no watch-path hit
    C-->>Pool: verdict: irrelevant
    Pool-->>O: poll collects #1200 → verified, journey ends
    Pool->>A: fetch files, Cargo.lock pin bump
    A-->>Pool: verdict: rev-sync
    Pool-->>O: poll collects #41 → verified
    O->>Pool: spawn_agent revsync-applier for #41 (detached)
    Note over A,B: #41's stage 2 starts while #900 is<br/>still in its FIRST stage
    Pool->>B: fetch files, generic logic in src/
    B-->>Pool: verdict: hoist
    Pool-->>O: poll collects #900 → verified
    O->>Pool: spawn_agent finding-filer for #900 (detached)
```

What the shape buys, and what it costs. Bought: a PR's journey never waits on a sibling, the
wall-clock reclaims one child without stalling 47 others, and each child's context holds one PR's
evidence instead of a batch of six. Cost: the orchestrator tracks ~N PRs, which is why per-PR state
lives in `run-ledger/` and its context holds the chart — it verifies a verdict by reading the
child's FILE, never by re-reading the envelope into its own context.

## 12. The draft/commit split

The stage-2 drafters and the committers are different agents. The drafters keep the judgment and
lose the write: `finding-filer` writes `run-ledger/filer/<slug>/draft.md` plus its evidence bundle
and returns `ready <slug>` / `already-filed` / `already-tracked` / `refused` / `blocked`;
`revsync-applier` clones, branches, and commits pin lines locally — never pushes — writing
`run-ledger/revsync/<slug>/branch.md` and the PR body and returning `ready` / `already-open #N` /
`blocker`; `rollup-writer` composes `run-ledger/rollup/target.md`, `state-body.md`, and
`comment.md` and writes nothing to GitHub. The judges re-verify those drafts live. Only then do the
committers — deliberately mechanical, because the intelligence is gated upstream — perform the
run's only GitHub writes, each idempotently so a retry can never duplicate an issue.

```mermaid
flowchart LR
    subgraph drafts["stage-2 drafts — run-ledger/ only, no GitHub writes"]
        FO["run-ledger/filer/<slug>/<br/>draft.md + evidence bundle"]
        BO["run-ledger/revsync/<slug>/<br/>branch.md + pr-body.md, never pushed"]
        RO["run-ledger/rollup/<br/>target.md + state-body.md + comment.md"]
    end
    FO -->|"ready / already-tracked / refused / blocked"| G{"pipeline-gate then pipeline-appeal<br/>verdict-judge panel 3 majority,<br/>appellate-judge panel 1 unanimous"}
    BO -->|"ready / already-open / blocker"| G
    RO -->|"drafts + exception list"| G
    G -->|"passed"| C{"file-commit / bump-commit / rollup-commit<br/>check-before-create, write byte-identically, verify"}
    C --> W["the lane's only GitHub write:<br/>finding issue, pin-bump PR, tracking-issue body + comment"]
    C --> OUT["run-ledger/outcomes/<br/>file-<slug>.md, bump-<slug>.md, rollup.md"]
```
