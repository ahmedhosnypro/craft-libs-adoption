# craft-libs-adoption — rules for agents and contributors

This repository automates a scan of the Craft Apps suite every six hours for merged pull requests relevant to shared libraries, files evidence-backed findings as issues on `ahmedhosnypro/craft-libs` (aligned with the read-only scope policy in `storytold/craft-libs/AGENTS.md`), and opens mechanical pin-bump pull requests on lagging app repos. Runs use the `craft-agent` action and a private model gateway. Mission mode is the default: the orchestrator and its subagents live in `.craft-agent/agents/`, and the run prompt is `missions/adopt-libs.md`. The judged workflow — `.craft-agent/workflows/adopt-libs.md`, which puts every GitHub write behind a panel gate and an appellate seat — is staged and parse-checked against the released craft-agent v0.0.5 binaries; CI keeps the mission as its default until the judged workflow passes its first live rehearsal.

## File map

| path | role |
|---|---|
| `.github/workflows/adopt-libs.yml` | The scan: cron at 00:20/06:20/12:20/18:20 UTC plus manual dispatch. Concurrency is event-scoped: scheduled runs serialize on one group, manual dispatches each join their own group (see the workflow's `concurrency` block) |
| `config/repo-list.txt` | Repos scanned, their archetypes, watch-paths, and candidate hypotheses |
| `missions/adopt-libs.md` | The phase-contract library the workflow step bodies cite and compress; also the mission-mode run prompt and the rollback path |
| `scripts/run-scan.sh` | Runs the scan using the release binaries and streams it live (the stream is visible in the log); `CRAFT_AGENT_WORKFLOW` set runs the judged workflow, unset runs the mission |
| `scripts/stream-render.py` | Live renderer of the run transcript: tool calls, spawn waves, subagent outcomes, usage, and conclusion; in workflow mode it also follows the run journal and the per-step session transcripts and heartbeats while a step is quiet |
| `.craft-agent/agents/` | The orchestrator (`lib-adoption-analyst`), five specialists (`source-cloner`, `merge-classifier`, `finding-filer`, `revsync-applier`, `rollup-writer`), two judges (`verdict-judge`, `appellate-judge`) and three committers (`finding-committer`, `revsync-committer`, `rollup-committer`) — validated by craft-agent's loader |
| `.craft-agent/workflows/adopt-libs.md` | The judged workflow: 16 steps, prepare → classify → panel gate → appellate → draft/commit pattern. Parse-checked and rehearsed in the storytell `sim/` container against the released v0.0.9 binaries (spawn tools live, bounded judges); a dispatch that sets the scan job's `workflow` input runs it, and CI keeps the mission as its default until it passes its first live cloud rehearsal |
| `.agents/skills/pooled-missions/` | The pooled-run skill: ledger and pool discipline followed by the orchestrator |
| `.agents/skills/mermaid-diagrams/` | The diagram skill used by finding-filer; extraction diagrams are validated before filing |
| `scripts/clone-sources.sh` | One clone attempt for the source sweep (sparse/full/tarball methods); called by source-cloner children |
| `sources/`, `run-ledger/` | Workspace scratch: per-window clone attempts for scanned repos and `storytold/craft-libs` (scope truth), plus agent ledgers. Clone outcomes must be recorded; scratch is never committed. |
| `rollups/` | Legacy rollup documents from the proposal-PR era; the scan now comments on the tracking issue and updates its state body on `ahmedhosnypro/craft-libs` |
| `docs/workflow-diagrams.md` | Mermaid visualizations of how the scan runs — both modes: the mission-mode job/phases/tree/verdict lifecycle, and the judged workflow's 16-step DAG, gate anatomy, and draft/commit split — kept in sync with the workflow, see "Keeping the workflow diagrams current" below |

## Running a scan

Actions tab → “Craft libs adoption scan” → Run workflow, or
`gh workflow run adopt-libs.yml -R ahmedhosnypro/craft-libs-adoption`.
Watch with `gh run watch`. Sources are not pre-cloned: the window is collected through the GitHub API, and the run attempts to clone its sources into `sources/`.

Today the scheduled and default dispatches run mission mode — unchanged behavior: `missions/adopt-libs.md` drives `lib-adoption-analyst`, which spawns the specialists that write directly to GitHub.

The judged workflow lives in `.craft-agent/workflows/adopt-libs.md` (frontmatter `name: adopt-libs`). It is the same scan gated: `scripts/run-scan.sh` switches to `craft-agent workflow --workflow adopt-libs` when `CRAFT_AGENT_WORKFLOW` is set, with the renderer following the run's journal and the per-step session transcripts for mid-step liveness. The craft-agent v0.0.5 release it needs is published, and the workflow parses cleanly on those binaries (verified with the released asset, sha256-verified: the plan, all eleven agent profiles, and the engine all load). The scan job now selects it: a `workflow_dispatch` run with the `workflow` input set to `adopt-libs` runs it; scheduled cron runs and an empty input keep the mission until the judged workflow has passed its first live rehearsal.

## Secrets (names only, set via GitHub settings)

`MODEL_API_URL`, `MODEL_API_KEY`, `MODEL_ID` — the model gateway. `PRIVATE_REPO_ACCESS_TOKEN` — reads private gateway backups and release assets, and grants the run's permitted write access: findings and the tracking issue on `ahmedhosnypro/craft-libs`, plus pin-bump pull requests on app repos (requires push access there). `GATEWAY_DB_PASSWORD`, `IR_MASTER_KEY` — the gateway database and its key vault.

## Laws every run obeys

- GitHub writes are limited to finding issues on `ahmedhosnypro/craft-libs`, the tracking issue's body and window comments there, and pin-bump branches/PRs on app repos (pin lines only). Do not comment on upstream issues or write to `storytold/craft-libs`; its `AGENTS.md` and scope policy are read-only references.
- Every claim is backed by verified evidence. Findings cite a merged PR and relevant file/patch evidence; pin bumps are based on verified app pin refs and the actual `craft-libs` revision. Never invent a merge, file, ref, or API result.
- Code is read from clones, not claims. Attempt a fresh clone for every repo in `config/repo-list.txt` plus `storytold/craft-libs` (scope truth). Record each clone's outcome; only a populated clone with a valid `HEAD` can supply code or duplication evidence. Duplication requires real paths plus PR/pin refs, or is marked `unverified`. The `candidates` column is a hypothesis, never evidence. Changes shipping non-source assets carry a licensing precondition.
- Read the authoritative scope policy from the `storytold/craft-libs` scope-truth clone every run; it outranks duplication arguments and governs how findings are framed.
- Never print secrets, environment values, git config values, headers, or token encodings. Keep local scratch files and ledgers inside the workspace root.
- Persistent GitHub artifacts are limited to the findings, permitted pin-bump PRs, and the tracking issue (`Adoption scan rollups`): one window comment and an updated state body per run. Rotate to a fresh tracking issue after more than 30 comments, preserving the prior body and linking the issues. No other GitHub writes are allowed. Under the judged workflow those writes happen only behind passed pre-write gates: the drafters return drafts and evidence bundles into `run-ledger/`, judges re-verify them, and the committers perform the only GitHub writes, idempotently.

## Changing the scan list

Edit `config/repo-list.txt` (archetype, watch-paths, and candidate hypotheses per repo). This file is the source of truth; when the list changes, update any explicit repo counts elsewhere in the mission or documentation.

## Keeping the workflow diagrams current

`docs/workflow-diagrams.md` documents how the scan runs in both modes: the CI job, the mission phases, the subagent tree, the capacity-grouped classification dispatch, the verdict lifecycle, the filer gates, the cadence, and the subagent budget (mission mode — the rollback path), plus the judged workflow's 16-step DAG, gate anatomy, and draft/commit split. Whenever any of those change — `.github/workflows/adopt-libs.yml` (steps, triggers, env), `missions/adopt-libs.md` (phases, caps, rules), `.craft-agent/workflows/adopt-libs.md` (step ids, gate configs, judge budget), `.craft-agent/agents/` (the team or its ledgers), or `scripts/` — update the diagrams in the same change. Diagram elements must keep naming the real file, step, phase, agent, or artifact, and every diagram must pass the bundled validator (`bun .agents/skills/mermaid-diagrams/scripts/validate-mermaid.ts docs/workflow-diagrams.md`) before the change is called done. Where a mission-mode diagram conflicts with the judged workflow, label it as the rollback path.
