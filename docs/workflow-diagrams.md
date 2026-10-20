# The adoption scan, visualized

How the six-hour craft-libs adoption scan actually runs: the GitHub Actions job in
`.github/workflows/adopt-libs.yml`, the mission phases from `missions/adopt-libs.md`, and the
subagent pool of `.craft-agent/agents/`. Every name below is a real file, step, phase, agent, or
artifact. One diagram per concept; nothing here invents entities.

## 1. The CI job — boot the gateway, run the scan

The job `scan` on `ubuntu-latest` (timeout 360 min). The private model gateway
(`ahmedhosnypro/ironrouter-backend`) is cloned, its Postgres registry restored on :5434, and the
binary serves on :17844 before `scripts/run-scan.sh` starts the agent. The pulse step is
best-effort: it never turns a green scan red.

```mermaid
flowchart TD
    Trigger["cron 20 0,6,12,18 * * *<br/>or workflow_dispatch"] --> Checkout["Check out the repository"]
    Checkout --> FetchGW["Fetch the model gateway<br/>ahmedhosnypro/ironrouter-backend"]
    FetchGW --> Postgres["Start the gateway database<br/>postgres:17 on :5434"]
    Postgres --> Restore["Restore the model registry<br/>pg_restore ironrouter-registry.dump"]
    Restore --> Migrate["Apply pending gateway migrations<br/>target/release/migration up"]
    Migrate --> StartGW["Start the model gateway<br/>target/release/app on :17844"]
    StartGW --> WaitGW["Wait for the gateway<br/>/healthz then /v1/models"]
    WaitGW --> Mission["Load the mission prompt<br/>missions/adopt-libs.md"]
    Mission --> RunScan["Run the adoption scan<br/>scripts/run-scan.sh, craft-agent --agent lib-adoption-analyst"]
    RunScan --> Transcript["Upload the run transcript<br/>run-transcript artifact"]
    Transcript --> Pulse["Keep the schedule alive<br/>scan pulse into .scan-log"]
```

## 2. The mission phases

The orchestrator `lib-adoption-analyst` computes the window itself (`date -u -d '7 hours ago'` —
a 7-hour look-back on the 6-hour cadence), reads the tracking issue's Mission State body and the
maintainer-verdict digest, then drives the five phases. Zero merges skips classification; the
clones still run because duplication is proven across the suite, not across the window.

```mermaid
flowchart TD
    Init["Run start: window, Mission State,<br/>maintainer-verdict digest, mission.db"] --> P1["Phase 1 — Collect the window<br/>REST sweep over 17 repos + craft-helpers cross-check"]
    P1 --> P1b["Phase 1b — Clone the sources<br/>17 repos + storytold/craft-libs scope-truth"]
    P1b --> Zero{"Any merges in window?"}
    Zero -->|Yes| P2["Phase 2 — Classify<br/>batches of ≤18 PRs, one repo each, newest-first"]
    P2 --> Wave{"Wave finished and verified?"}
    Wave -->|No| P2
    Wave -->|Yes| P3["Phase 3 — File findings + pin bumps<br/>≤3 filers, ≤3 appliers, one turn"]
    Zero -->|No| P3
    P3 --> Stop{"Turn 180 stop rule"}
    Stop --> P4["Phase 4 — Deliver<br/>rollup-writer spawn_agent"]
    P4 --> Body["Mission State body<br/>on tracking issue Adoption scan rollups"]
    P4 --> Comment["Window comment<br/>3–8 lines + one Signal line per active repo"]
```

## 3. The run as a sequence

The orchestrator never classifies, files, or delivers itself; each phase is a wave of specialist
children, and every child deliverable is verified against `gh api` before the next wave starts.

```mermaid
sequenceDiagram
    participant O as lib-adoption-analyst
    participant C as source-cloner
    participant M as merge-classifier
    participant G as per-PR grandchild
    participant F as finding-filer
    participant A as revsync-applier
    participant R as rollup-writer
    O->>O: Compute window, read Mission State, build verdict digest
    O->>C: spawn_agents — 18 clone items (scan-source, scope-truth)
    C-->>O: clone-ok / clone-degraded / clone-blocked per repo
    O->>M: spawn_agents — batch-01..batch-NN (≤32 batches per call)
    M->>G: spawn_agents — one item per PR in the batch
    G-->>M: pr-<number>.verdict line
    M-->>O: batch report (verdict count equals batch size)
    O->>F: spawn_agents — ≤3 finding items (same turn)
    O->>A: spawn_agents — ≤3 bump candidates (same turn)
    F-->>O: issue filed as adoption-scan: <slug>
    A-->>O: pin-bump PR or recorded blocker
    O->>R: spawn_agent — composed state snapshot
    R-->>O: Mission State body + window comment verified
```

## 4. The subagent tree

Depth 3 by design and never deeper: coordinators may spawn grandchildren, grandchildren never
spawn. Every spawn carries `maxTurns: 10000`, `timeoutSecs: 0`, `maxTokens: 75000000` — omitting
`maxTokens` starves later waves of the run's 5,000,000,000-token budget.

```mermaid
flowchart LR
    O["lib-adoption-analyst<br/>depth 0"] --> C["source-cloner ×18<br/>depth 1"]
    O --> M["merge-classifier<br/>depth 1, one per batch"]
    M --> G["per-PR grandchild<br/>depth 2, one spawn_agents per batch"]
    O --> F["finding-filer ×≤3<br/>depth 1"]
    O --> A["revsync-applier ×≤3<br/>depth 1"]
    O --> R["rollup-writer ×1<br/>depth 1, spawn_agent"]
```

## 5. Inside one classification wave

A batch child never loops over its PRs. Its four moves — claim, spawn, verify and report, close —
and the grandchildren's three describe the fastest honest path; turn counts are guidance, not caps.

```mermaid
sequenceDiagram
    participant Coord as merge-classifier batch child
    participant Kid as per-PR grandchild
    participant Ledger as run-ledger/classifier/batch-<NN>/
    participant API as GitHub REST API
    Coord->>Ledger: scope-claim batch-<NN>
    Coord->>Coord: Split batch into per-PR prompts
    Coord->>Kid: spawn_agents — one item per PR
    Kid->>API: GET changed-file list + patch/diff
    Kid->>Ledger: task row + pr-<number>.verdict
    Kid-->>Coord: verdict line as final message
    Coord->>Ledger: Verify verdict files, write batch report
    Coord->>Ledger: scope-done
```

## 6. A PR's verdict lifecycle

Verdict classes come from `missions/adopt-libs.md`: `rev-sync`, `hoist`, `port`, `irrelevant`,
`unverified`, or `maturing:<slug>`. A maturing candidate reaches filing only after corroboration in
two consecutive windows, and only when the maintainer-verdict digest's revival conditions allow it.

```mermaid
stateDiagram-v2
    [*] --> Collected: merged_at >= window start
    Collected --> Batched: batch-NN, newest-first
    Batched --> Fetched: changed-file list + patch
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

At most 256 subagents per run, at most 64 concurrent tree-wide. The reserve covers the 18 cloners,
up to 6 filers/appliers, the rollup child, and retries; the rest is classifier coordinators and
per-PR grandchildren. Beyond the cap the run classifies newest-first and reports the unclassified
count as an exception.

```mermaid
pie showData title Subagents within the 256-per-run cap
    "Cloners — 17 repos + storytold/craft-libs" : 18
    "Classifier coordinators + per-PR grandchildren" : 210
    "Filers + appliers" : 6
    "Rollup child + retry reserve" : 22
```

