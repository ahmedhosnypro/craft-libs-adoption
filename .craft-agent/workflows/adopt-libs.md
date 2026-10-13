---
# STAGED, NOT WIRED INTO CI: the craft-agent `workflow` mission
# ships in the release AFTER v1.1.0 (the workflow layer landed
# unreleased). Until those binaries exist, the 6h scan runs the
# monolithic mission.md. This file is kept parse-valid against
# the plan schema so wiring it later is a workflow edit only.
name: craft-libs-adoption-01
description: 6h merged-PR scan; classify craft-libs relevance; open evidence-citing proposal PRs.
args:
  window: { type: string, default: 7h }
  scan-org: { type: string, default: storytold }
  delivery-repo: { type: string, default: ahmedhosnypro/craft-libs }
limits:
  max-steps: 6
  max-total-turns: 160
  max-total-tokens: 4000000
  max-retries-per-step: 1
steps:
  - id: collect
    agent: adoption-libs
    model: glm-5.3-flash
    needs: []
    max-turns: 25
    retry: 1
    on-failure: stop
    outputs: [pr-inventory, worklog]
    body: |
      Read config/repo-list.txt (one repository per line, `#`
      comments, blank lines ignored) and run ONE sweep, ONCE:
      `craft-helpers prs --org {{arg.scan-org}} --repos
      <comma-joined list from the file> --since {{arg.window}}
      --limit-per-repo 30 --max-prs 500 --json` into
      /runner/temp/prs.json. The window is 7h on the 6h cadence
      — the 1h pad absorbs cron lateness. Then write the worklog
      /runner/temp/<today>-scan-worklog.md (<today> from
      `date -u +%F`): UTC window bounds, repository count, every
      truncated marker and fetch-failure row verbatim. Final
      message: the window bounds, per-repository merged counts,
      and every collection marker.
  - id: classify
    agent: adoption-libs
    model: glm-5.3-flash
    needs: [collect]
    max-turns: 35
    retry: 1
    on-failure: stop
    outputs: [classification]
    body: |
      Read /runner/temp/prs.json and classify every merged pull
      request from the JSON alone — irrelevant (application
      feature, the default) or actionable — one worklog line
      each with a reason. Actionable signals: a craft-* git
      dependency change; changed files under a crate another
      scanned repository carries; the same change in two
      repositories this window; extraction/shared/port wording;
      a new generic crate directory. Deep-verify at most 3
      candidates with `gh pr view`/`gh pr diff` (read-only), one
      attempt each. Final message: the actionable findings ranked
      by strength, each with its merged-PR URL(s) and type — new
      shared-lib candidate or drift on an already-shared crate.
  - id: propose
    agent: adoption-libs
    model: glm-5.3-flash
    needs: [classify]
    max-turns: 40
    retry: 1
    on-failure: stop
    outputs: [proposal-docs]
    body: |
      The workflow provides the clone of {{arg.delivery-repo}} at
      /runner/temp/craft-libs; work only inside it. Skip a
      finding whose evidence URL already appears under docs/ in
      the clone — an earlier run carried it. For each ranked
      finding write one doc, skeleton-first, at
      most 120 lines, no code extraction in v1. New shared-lib
      candidate → docs/proposals/<today>-<slug>.md: rationale,
      evidence (merged-PR URLs), file inventory, target crate
      mapping. Drift on a shared crate → a dated note appended
      to docs/crates/<crate>.md. Findings beyond the top 2 also
      get entries in docs/proposals/<today>-rollup.md. Final
      message: the doc paths, one line each on what they propose
      and the evidence they cite.
  - id: deliver
    agent: adoption-libs
    model: glm-5.3-flash
    needs: [propose]
    max-turns: 50
    retry: 1
    on-failure: stop
    outputs: [opened-prs]
    body: |
      Open the pull requests on {{arg.delivery-repo}}, hard cap
      3 counting every pull request: one per finding for the top
      2, the rollup doc as the third when more exist; with zero
      findings, one pull request adding
      docs/scans/<today>-<slug>.md — the scan digest: window
      bounds, repositories scanned, classification tally,
      near-misses. Branch agent/<today>-<slug>, suffixing -2 then
      -3 on collisions — never reuse an existing branch. Commit
      explicit paths with a conventional message, push, then
      `gh pr create --repo {{arg.delivery-repo}} --base main`;
      every body opens with the UTC window bounds and cites the
      merged-PR evidence. The worklog never enters a commit.
      Final message: only what THIS run created — pull request
      URLs, the docs they carry, every collection marker.
---
# Shared rules — prepended to every step

- READ-ONLY on every scanned repository: list, view, and diff
  only; every write goes to {{arg.delivery-repo}}.
- Measured facts only: every claim links its merged pull
  request; unknown is stated as unknown; truncated or failed
  collection is reported, never hidden.
- Never run builds or tests; install nothing; work only in the
  workspace and /runner/temp; never print environment variables
  or secrets.
- Self-attribution: name only artifacts this run created;
  existing branches and pull requests never satisfy a
  deliverable.
- Deliver-completeness: the run fails unless it attempts at
  least one pull request on {{arg.delivery-repo}}; an empty
  window delivers the scan digest.
- `<today>` is the UTC date (`date -u +%F`) taken at run start.
