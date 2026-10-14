# craft-libs-adoption — rules for agents and contributors

This repository is an automation: it scans the Craft Apps suite every
six hours for merged pull requests relevant to the shared libraries,
files evidence-backed findings as issues on `ahmedhosnypro/craft-libs`
(aligned with its RFC convention and its extraction map, issue #94),
and opens mechanical pin-bump pull requests on lagging app repos. The
runs are performed by the `craft-agent` action talking to a private
model gateway; the analysis persona lives in
`.craft-agent/agents/lib-adoption-analyst.md` and the mission in
`missions/adopt-libs.md`.

## File map

| path | role |
|---|---|
| `.github/workflows/adopt-libs.yml` | the scan: cron at 00:20/06:20/12:20/18:20 UTC + manual dispatch |
| `config/repo-list.txt` | the repos scanned, their archetypes, watch-paths, candidates |
| `missions/adopt-libs.md` | the mission text the agent executes |
| `.craft-agent/agents/lib-adoption-analyst.md` | the persona (validated by craft-agent's loader) |
| `rollups/` | legacy: rollup documents from the proposal-PR era; the scan now posts rollups as comments on the upstream tracking issue |

## Running a scan

Actions tab → "Craft libs adoption scan" → Run workflow, or
`gh workflow run adopt-libs.yml -R ahmedhosnypro/craft-libs-adoption`.
Watch with `gh run watch`. A run needs no repositories cloned here:
collection happens through the GitHub API inside the run.

## Secrets (names only, set via GitHub settings)

`MODEL_API_URL`, `MODEL_API_KEY`, `MODEL_ID` — the model gateway the
run talks to. `PRIVATE_REPO_ACCESS_TOKEN` — reads the private gateway
backup and release assets, and carries the run's write rights: issues
on `ahmedhosnypro/craft-libs` and pin-bump pull requests on the app repos
(requires push on those repos). `GATEWAY_DB_PASSWORD`, `IR_MASTER_KEY`
— the gateway database and its key vault.

## Laws every run obeys

- Writes are allowed only in two shapes: issues and issue comments on
  `ahmedhosnypro/craft-libs`; pin-bump branches and pull requests on the
  app repos (pin lines only). Everything else in storytold/* is
  read-only. `ahmedhosnypro/craft-libs` receives no writes; it is a
  mirror.
- Every finding and bump cites merged pull requests as evidence;
  none is invented.
- The shared library's own AGENTS.md and scope policy are read every
  run and win over any argument from duplication; the extraction map
  (ahmedhosnypro/craft-libs#94) governs where findings land.
- Each run leaves exactly its traces: finding issues or comments,
  pin-bump pull requests, and one rollup comment on the tracking
  issue — nothing else, ever.

## Changing the scan list

Edit `config/repo-list.txt` (archetype, watch-paths, candidates per
repo). The list is data, not code — the mission reads it at runtime.
