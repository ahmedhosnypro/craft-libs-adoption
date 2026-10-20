# craft-libs-adoption — rules for agents and contributors

This repository automates a scan of the Craft Apps suite every six hours for merged pull requests relevant to shared libraries, files evidence-backed findings as issues on `ahmedhosnypro/craft-libs` (aligned with the read-only scope policy in `storytold/craft-libs/AGENTS.md`), and opens mechanical pin-bump pull requests on lagging app repos. Runs use the `craft-agent` action and a private model gateway; the orchestrator and five specialist subagents live in `.craft-agent/agents/`, and the mission is in `missions/adopt-libs.md`.

## File map

| path | role |
|---|---|
| `.github/workflows/adopt-libs.yml` | The scan: cron at 00:20/06:20/12:20/18:20 UTC plus manual dispatch |
| `config/repo-list.txt` | Repos scanned, their archetypes, watch-paths, and candidate hypotheses |
| `missions/adopt-libs.md` | The mission text the agent executes |
| `scripts/run-scan.sh` | Runs the scan using the release binaries and streams it live (the stream is visible in the log) |
| `scripts/stream-render.py` | Live renderer of the run transcript: tool calls, spawn waves, subagent outcomes, usage, and conclusion |
| `.craft-agent/agents/` | The orchestrator (`lib-adoption-analyst`) and five specialists (`source-cloner`, `merge-classifier`, `finding-filer`, `revsync-applier`, `rollup-writer`) — validated by craft-agent's loader |
| `.agents/skills/pooled-missions/` | The pooled-run skill: ledger and pool discipline followed by the orchestrator |
| `.agents/skills/mermaid-diagrams/` | The diagram skill used by finding-filer; extraction diagrams are validated before filing |
| `scripts/clone-sources.sh` | One clone attempt for the source sweep (sparse/full/tarball methods); called by source-cloner children |
| `sources/`, `run-ledger/` | Workspace scratch: per-window clone attempts for scanned repos and `storytold/craft-libs` (scope truth), plus agent ledgers. Clone outcomes must be recorded; scratch is never committed. |
| `rollups/` | Legacy rollup documents from the proposal-PR era; the scan now comments on the tracking issue and updates its state body on `ahmedhosnypro/craft-libs` |

## Running a scan

Actions tab → “Craft libs adoption scan” → Run workflow, or
`gh workflow run adopt-libs.yml -R ahmedhosnypro/craft-libs-adoption`.
Watch with `gh run watch`. Sources are not pre-cloned: the window is collected through the GitHub API, and the run attempts to clone its sources into `sources/`.

## Secrets (names only, set via GitHub settings)

`MODEL_API_URL`, `MODEL_API_KEY`, `MODEL_ID` — the model gateway. `PRIVATE_REPO_ACCESS_TOKEN` — reads private gateway backups and release assets, and grants the run's permitted write access: findings and the tracking issue on `ahmedhosnypro/craft-libs`, plus pin-bump pull requests on app repos (requires push access there). `GATEWAY_DB_PASSWORD`, `IR_MASTER_KEY` — the gateway database and its key vault.

## Laws every run obeys

- GitHub writes are limited to finding issues on `ahmedhosnypro/craft-libs`, the tracking issue's body and window comments there, and pin-bump branches/PRs on app repos (pin lines only). Do not comment on upstream issues or write to `storytold/craft-libs`; its `AGENTS.md` and scope policy are read-only references.
- Every claim is backed by verified evidence. Findings cite a merged PR and relevant file/patch evidence; pin bumps are based on verified app pin refs and the actual `craft-libs` revision. Never invent a merge, file, ref, or API result.
- Code is read from clones, not claims. Attempt a fresh clone for every repo in `config/repo-list.txt` plus `storytold/craft-libs` (scope truth). Record each clone's outcome; only a populated clone with a valid `HEAD` can supply code or duplication evidence. Duplication requires real paths plus PR/pin refs, or is marked `unverified`. The `candidates` column is a hypothesis, never evidence. Changes shipping non-source assets carry a licensing precondition.
- Read the authoritative scope policy from the `storytold/craft-libs` scope-truth clone every run; it outranks duplication arguments and governs how findings are framed.
- Never print secrets, environment values, git config values, headers, or token encodings. Keep local scratch files and ledgers inside the workspace root.
- Persistent GitHub artifacts are limited to the findings, permitted pin-bump PRs, and the tracking issue (`Adoption scan rollups`): one window comment and an updated state body per run. Rotate to a fresh tracking issue after more than 30 comments, preserving the prior body and linking the issues. No other GitHub writes are allowed.

## Changing the scan list

Edit `config/repo-list.txt` (archetype, watch-paths, and candidate hypotheses per repo). This file is the source of truth; when the list changes, update any explicit repo counts elsewhere in the mission or documentation.
