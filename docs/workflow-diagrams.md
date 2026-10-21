# The adoption scan, visualized

How the six-hour craft-libs adoption scan actually runs: the GitHub Actions job in
`.github/workflows/adopt-libs.yml`, the mission phases from `missions/adopt-libs.md`, and the
subagent pool of `.craft-agent/agents/`. Every name below is a real file, step, phase, agent, or
artifact. One diagram per concept; nothing here invents entities.

Two modes are drawn here. **Mission mode** (sections 1–9) is today's CI default and the rollback
path: `lib-adoption-analyst` drives the phases itself and the specialists write to GitHub directly.
**Workflow mode** (sections 10–12) is the judged DAG in `.craft-agent/workflows/adopt-libs.md` —
16 steps gating every GitHub write behind a panel and an appellate verdict. Mission mode is the
current reality; workflow mode is what the same run becomes, so where the two conflict the
mission-mode sections describe the rollback path, not the destination.

## 1. The CI job — boot the gateway, run the scan

The job `scan` on `ubuntu-latest` (timeout 360 min). The private model gateway
(`ahmedhosnypro/ironrouter-backend`) is cloned, its Postgres registry restored on :5434, and the
binary serves on :17844 before `scripts/run-scan.sh` starts the agent. The pulse step is
best-effort: it never turns a green scan red.

Mission mode (the current default and the rollback path): the `Load the mission prompt` step reads
`missions/adopt-libs.md`, and `scripts/run-scan.sh` runs `craft-agent run --agent
lib-adoption-analyst --prompt <mission file>`. Workflow mode swaps that for `craft-agent workflow
--workflow adopt-libs` (no `--max-tokens` — it is a per-step cap), with the renderer following the
run's journal (step events) and the per-step session transcripts (prompts, tool calls, tool results)
under `.craft-agent/workflows/<run_id>/` for mid-step liveness; `run-scan.sh` selects it from
`CRAFT_AGENT_WORKFLOW`, which the `workflow` dispatch input sets; scheduled runs and an empty input
keep mission mode until the first live rehearsal — see section 10. Concurrency is event-scoped:
scheduled runs serialize on one group (`adopt-libs-scheduled`), and every manual dispatch joins its own
group (`adopt-libs-${{ github.run_id }}`), so a mission scan and a workflow rehearsal can run at the
same time — the tracking-issue state update and the `already-filed`/`already-open` checks are the
racy surfaces those parallel runs share.

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
    Mission --> RunScan["Run the adoption scan<br/>scripts/run-scan.sh, craft-agent run --agent lib-adoption-analyst"]
    RunScan --> Transcript["Upload the run transcript<br/>run-transcript artifact"]
    Transcript --> Pulse["Keep the schedule alive<br/>scan pulse into .scan-log"]
```

## 2. The mission phases

**Mission mode — the rollback path.** The orchestrator `lib-adoption-analyst` computes the window
itself (`date -u -d '7 hours ago'` — a 7-hour look-back on the 6-hour cadence), reads the tracking
issue's Mission State body and the maintainer-verdict digest, then drives the five phases. Zero
merges skips classification; the clones still run because duplication is proven across the suite,
not across the window.

Under the judged workflow (section 10) the same phases become steps: `prepare` runs Phase 1 + Phase
1b plus verification, `classify` runs Phase 2, and the specialists no longer write to GitHub at all.

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

**Rollback-path note:** the arrows below are mission mode. Under the judged workflow the filer,
applier, and rollup children only produce drafts in `run-ledger/`; the writes shown here move to
the committers behind the gates of section 11.

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

At most 256 subagents per run, at most 64 concurrent tree-wide. The reserve covers the 18 cloners,
up to 6 filers/appliers, the rollup child, and retries; the rest is classifier coordinators and
per-PR grandchildren. Beyond the cap the run classifies newest-first and reports the unclassified
count as an exception.

**Rollback-path note:** this pie is mission mode's pool. Under the judged workflow the engine
sequences the 16 steps itself (`max-concurrent-steps: "4"`) and each dispatcher step still spawns
its own specialist waves, bounded instead by the run's `max-total-turns: "10000"` and
`max-total-tokens: "100000000"` pool.

```mermaid
pie showData title Subagents within the 256-per-run cap
    "Cloners — 17 repos + storytold/craft-libs" : 18
    "Classifier coordinators + per-PR grandchildren" : 210
    "Filers + appliers" : 6
    "Rollup child + retry reserve" : 22
```

---

## 10. The judged workflow — the 16-step DAG

Workflow mode lives in `.craft-agent/workflows/adopt-libs.md` (frontmatter `name: adopt-libs`, arg
`window` default `7h`) — the same scan, but the engine sequences the steps instead of the
orchestrator, and every GitHub write sits behind a verdict. Limits: `max-steps: "16"` (the hard cap,
so the DAG is exactly full — a new phase means a consolidation, not a 17th step),
`max-concurrent-steps: "4"`, `max-total-turns: "10000"`, `max-total-tokens: "100000000"`,
`max-retries-per-step: "2"`. Every step states `max-turns`, `retry`, and `on-failure` explicitly —
never relying on the 25/0/stop defaults.

The shape: one shared spine (`prepare`, `classify`, `classify-gate`, `classify-appeal`) then three
parallel islands that never touch each other — file (5–8), bump (9–12), rollup (13–16). Only
success releases dependants, so what happens after a failure depends on that step's `on-failure`.

**Failure policy — schema-enforced, not a preference.** A step the run survives a failure of
(`skip` or `warn`) must be a leaf: the workflow schema forbids `skip`/`warn` on a step that has
dependants, or the pipeline stalls. So all 13 steps anything depends on are `stop`, and only the
three leaf committers — nothing needs them — are `skip`. A gate that settles failed therefore halts
admissions: the run ends `Failed` (exit 1 on a step error, 2 on max-turns, 3 on budget), its appeal
and commit settle as skipped with a named `DependencyFailed` reason (journaled, never silent), and
the next run heals from the prior state body. A skipped *committer* still records the failure (the
run is `Failed`), but in-flight sibling branches keep running, so their terminal rows reach the
rollup's exception list — that is the audit trail for a failed lane.

`rollup-draft` composes the snapshot from the terminal `run-ledger/outcomes/*.md` rows and the
journal — skipped steps become named exceptions, never silence — with a bounded wait (≤45 min) for
the file and bump lanes, and never claims an artifact it cannot verify. Worst case is ≈5 000 turns
against the 10 000 pool (dispatchers ~2 900; four gates × 3 seats × up to 3 verdict rounds ~1 100;
committers ~480). `max-feedback: "0"` on the appellate seats is what makes their `needs:
[<judge>]` legal — feedback may never target another judge.

```mermaid
flowchart TD
    P["1 prepare — lib-adoption-analyst<br/>window sweep + Phase 1b clone wave + verdict digest"] --> C["2 classify — lib-adoption-analyst<br/>Phase 2 waves, capacity-safe"]
    C --> CG{"3 classify-gate<br/>verdict-judge, panel 3, majority"}
    CG -->|pass| CA{"4 classify-appeal<br/>appellate-judge, panel 1, unanimous"}

    subgraph file["file island — steps 5-8"]
        direction TB
        FD["5 file-draft — lib-adoption-analyst"] --> FG{"6 file-gate<br/>verdict-judge, panel 3, majority"}
        FG -->|pass| FA{"7 file-appeal<br/>appellate-judge, panel 1, unanimous"}
        FA -->|uphold| FC["8 file-commit — finding-committer"]
        FG -.->|"fail: gate stops the run (skips below it, named)"| FC
    end

    subgraph bump["bump island — steps 9-12"]
        direction TB
        BD["9 bump-draft — lib-adoption-analyst"] --> BG{"10 bump-gate<br/>verdict-judge, panel 3, majority"}
        BG -->|pass| BA{"11 bump-appeal<br/>appellate-judge, panel 1, unanimous"}
        BA -->|uphold| BC["12 bump-commit — revsync-committer"]
        BG -.->|"fail: gate stops the run (skips below it, named)"| BC
    end

    subgraph rollup["rollup island — steps 13-16"]
        direction TB
        RD["13 rollup-draft — lib-adoption-analyst"] --> RG{"14 rollup-gate<br/>verdict-judge, panel 3, majority"}
        RG -->|pass| RA{"15 rollup-appeal<br/>appellate-judge, panel 1, unanimous"}
        RA -->|uphold| RC["16 rollup-commit — rollup-committer"]
        RG -.->|"fail: gate stops the run (skips below it, named)"| RC
    end

    P -->|"needs: prepare only"| RD
    CA -->|uphold| FD
    CA -->|uphold| BD
    CG -.->|"fail: run stops; both islands settle skipped (DependencyFailed)"| FD
    CG -.->|"fail: run stops; both islands settle skipped (DependencyFailed)"| BD
```

The dotted edges show what a failed gate does: admissions halt, and everything below the gate
settles as skipped with a named `DependencyFailed` reason — the failed lane's appeal and commit never
run, the other islands finish if already in flight, and the run's conclusion is `Failed` (exit 1 on a
step error, 2 on max-turns, 3 on budget) with the journal carrying every reason.

## 11. One gate — producer, panel, appellate, commit

Every lane is the same four-step shape. Behind each `*-draft` sits a panel of three
`verdict-judge` seats (`panel: "3"`, `merge: majority`, `max-feedback: "2"`, `deny-write` every
path), then a one-seat `appellate-judge` (`panel: "1"`, `merge: unanimous`, `max-feedback: "0"`),
then the mechanical committer. Seats run concurrently inside one step — one engine concurrency
slot — and each seat's final message is exactly `{"verdict":"pass"|"fail","issues":[...]}`; the
merged verdict is the step's settled final message. A majority needs strictly more pass votes, so a
tie fails; unanimous needs every seat. The producer's claims are not evidence: a seat re-reads the
artifacts and re-verifies live with read-only `gh` (`gh api`, `gh issue/pr view` — never a write).

A fail issue names what the rubric requires, what the work shows, and where the proof lives; a
failed verdict then requeues the producer with a `## Judge feedback` section (journaled as
`FeedbackRetried`) and the panel re-runs, bounded per producer by `max-feedback 2`. Still failing
after that budget, the gate settles failed and its `on-failure` decides the rest. The appellate seat
is the check on the panel: it re-derives the verdict from the cited evidence rather than counting
votes, overturns one it cannot reproduce, and treats rubric-out-of-scope requests as no grounds for
failure. Because a seat that errors fails the whole judge step as an error rather than a verdict,
judge steps carry generous `max-turns` (45–60) and `retry: 1`.

```mermaid
flowchart TD
    PROD["file-draft — lib-adoption-analyst<br/>draft + evidence bundle into run-ledger/filer/<slug>/"] --> PANEL{"file-gate — verdict-judge<br/>panel 3, merge majority, max-feedback 2<br/>rubric: merges resolve live, duplication proven,<br/>scope policy read, anchors resolved, one validated mermaid"}
    PANEL -->|"pass: more pass votes"| APP{"file-appeal — appellate-judge<br/>panel 1, merge unanimous, max-feedback 0"}
    APP -->|"uphold"| COMMIT["file-commit — finding-committer<br/>idempotent: check by title, create, verify"]
    PANEL -->|"fail: requeue the producer with ## Judge feedback"| PROD
    PANEL -->|"still failing after the budget: gate settles failed"| SKIP["on-failure: stop halts admissions<br/>the appeal and commit settle skipped,<br/>named DependencyFailed (only leaf committers may skip)"]
    APP -->|"fail"| SKIP
```

## 12. The draft/commit split

The drafters and the committers are different agents. The drafters keep the judgment and lose the
write: `finding-filer` writes `run-ledger/filer/<slug>/draft.md` plus its evidence bundle and
returns `ready <slug>` / `already-filed` / `already-tracked` / `refused` / `blocked`;
`revsync-applier` clones, branches, and commits pin lines locally — never pushes — writing
`run-ledger/revsync/<slug>/branch.md` and `pr-body.md` and returning `ready` / `already-open #N` /
`blocked`; `rollup-writer` composes `run-ledger/rollup/target.md`, `state-body.md`, and
`comment.md` and writes nothing to GitHub. The judges re-verify those drafts live. Only then do the
committers — deliberately mechanical, because the intelligence is gated upstream — perform the
run's only GitHub writes, each idempotently so a retry can never duplicate an issue.

```mermaid
flowchart LR
    subgraph drafts["draft steps — run-ledger/ only, no GitHub writes"]
        FD["file-draft"] --> FO["run-ledger/filer/<slug>/<br/>draft.md + evidence bundle"]
        BD["bump-draft"] --> BO["run-ledger/revsync/<slug>/<br/>branch.md + pr-body.md, never pushed"]
        RD["rollup-draft"] --> RO["run-ledger/rollup/<br/>target.md + state-body.md + comment.md"]
    end
    FO -->|"ready / already-tracked / refused / blocked"| G{"*-gate then *-appeal<br/>verdict-judge panel 3 majority,<br/>appellate-judge panel 1 unanimous"}
    BO -->|"ready / already-open / blocked"| G
    RO -->|"drafts + exception list"| G
    G -->|"passed"| C{"file-commit / bump-commit / rollup-commit<br/>check-before-create, write byte-identically, verify"}
    C --> W["the lane's only GitHub write:<br/>finding issue, pin-bump PR, tracking-issue body + comment"]
    C --> OUT["run-ledger/outcomes/<br/>file-<slug>.md, bump-<slug>.md, rollup.md"]
```

