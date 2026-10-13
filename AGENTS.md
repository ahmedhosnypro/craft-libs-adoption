# craft-libs-adoption — rules for agents and contributors

This repository is an automation: it scans the Craft Apps suite every
six hours for merged pull requests relevant to the shared libraries,
and opens evidence-backed proposal pull requests on
`ahmedhosnypro/craft-libs`. The runs are performed by the
`craft-agent` action talking to a private model gateway; the analysis
persona lives in `.craft-agent/agents/lib-adoption-analyst.md` and
the mission in `missions/adopt-libs.md`.

## File map

| path | role |
|---|---|
| `.github/workflows/adopt-libs.yml` | the scan: cron at 00:20/06:20/12:20/18:20 UTC + manual dispatch |
| `config/repo-list.txt` | the repos scanned, their archetypes, watch-paths, candidates |
| `missions/adopt-libs.md` | the mission text the agent executes |
| `.craft-agent/agents/lib-adoption-analyst.md` | the persona (validated by craft-agent's loader) |
| `rollups/` | created by runs: the per-window rollup documents |

## Running a scan

Actions tab → "Craft libs adoption scan" → Run workflow, or
`gh workflow run adopt-libs.yml -R ahmedhosnypro/craft-libs-adoption`.
Watch with `gh run watch`. A run needs no repositories cloned here:
collection happens through the GitHub API inside the run.

## Secrets (names only, set via GitHub settings)

`MODEL_API_URL`, `MODEL_API_KEY`, `MODEL_ID` — the model gateway the
run talks to. `PRIVATE_REPO_ACCESS_TOKEN` — reads the private gateway
backup and release assets, and carries the run's push/pull-request
rights on the target fork (the builtin token cannot write another
repository). `GATEWAY_DB_PASSWORD`, `IR_MASTER_KEY` — the gateway
database and its key vault.

## Laws every run obeys

- storytold/* is read-only, forever. All writes — branches and pull
  requests — go to `ahmedhosnypro/craft-libs` only.
- Every proposal cites merged pull requests as evidence; none is
  invented.
- The target repository's own AGENTS.md and scope policy are read
  every run and win over any argument from duplication.
- Each run leaves exactly one visible trace: its proposal pull
  requests, or a rollup pull request when the window was quiet.

## Changing the scan list

Edit `config/repo-list.txt` (archetype, watch-paths, candidates per
repo). The list is data, not code — the mission reads it at runtime.
