---
name: pooled-missions
description: >
  Run any decomposable mission with a fixed-size pool of parallel background
  subagents, tracked in a per-run sqlite DB with crash-safe resume and a
  final gated verification. Use whenever the user asks to run a mission
  with a pool of subagents — "pool this mission", "use N parallel
  subagents", "agent pool", "pooled" — or names work whose scope exceeds
  what one agent should handle alone: batch-fix or refactor many files,
  translate/audit/migrate/tag a whole tree or a long list, process hundreds
  of items (docs, locales, endpoints, tickets, URLs, images, config files)
  in parallel, or "do everything found" end-to-end with tracked outcomes.
  Missions may be code or non-code. Do NOT use when a dedicated pooled
  skill already owns the mission (full-repo code review, code-health
  remediation, quality gates with their own pool doctrine) — defer to it.
  Do NOT use for single-scope work one agent handles alone, or when the
  user asks for a foreground interactive task.
version: 1.0.0
---

# pooled-missions

Run any decomposable mission with a fixed-size pool of parallel background
subagents. Every work item lives in a per-run sqlite tracking DB, so the run
is crash-safe (any interrupted agent resumes without lost work), uniformly
disciplined (one protocol file governs every worker), and verifiable (a
final gate plus the DB as the complete ledger).

## Purpose

- Any mission, any domain: code fixes, refactors, docs, translations,
  migrations, audits, tagging, data processing — anything that decomposes
  into countable work items.
- One engine: the DB, the scope partitioning, the protocol file, the pool
  discipline, and the recovery rules are mission-independent; only the
  scope list, the protocol content, and the acceptance gate are defined
  per mission.
- Crash-safe orchestration: every claim, completion, and event transitions
  through a DB row, so an interrupted run — agent, harness, or app restart —
  resumes from the DB alone.

## The helper script

```
DBCTL=~/.agents/skills/pooled-missions/scripts/pool-db.sh
```

Subcommands (all timestamps are stamped by sqlite `datetime('now')` at the
moment of the write; every write runs under a 15s busy timeout):

- `init <db>` — create the schema (idempotent).
- `scope-add <db> <name> <items-csv>` — register a scope with its explicit
  item list; status `pending`.
- `scope-list <db> [status]` — list scopes (all, or one status).
- `scope-claim <db> <name> <agent-id>` — `pending → in_work`, records the
  claiming agent.
- `scope-done <db> <name> [note]` — `in_work → done`.
- `scope-fail <db> <name> <reason>` — `in_work → failed`.
- `task-add <db> <scope> <item> [detail]` — record a work item/finding.
- `task-done <db> <id> [note]` / `task-wontfix <db> <id> <reason>`.
- `event <db> <kind> <detail>` — append to the run ledger.
- `status <db>` — one-line dashboard: per-status scope and task counts, the
  DB clock, and the oldest `updated_at` among non-terminal rows (stall
  detection input).

Requires `sqlite3`. If it is missing, the script aborts with a one-line
actionable error; the degraded fallback is below.

## Steps

1. **Mission intake.** Before any machinery runs, define the mission in
   three sentences the user would endorse:
   - *Work items*: the countable units (files, modules, docs, locales,
     endpoints, tickets, URLs, images — anything enumerable).
   - *Done criteria*: what "complete" means for one scope, measurable by a
     worker with no extra context.
   - *Mode*: act (change things) or report-only (observe and record). Mode
     comes from the user's ask; acting never starts unasked. If the mission
     is vague, settle intake with the user first — a pool amplifies a wrong
     brief as efficiently as a right one.

2. **Preflight.**
   - `command -v sqlite3` — if missing, either ask the user to install it or
     fall back to the degraded mode at the end of this file.
   - `df -h .` — warn the user below ~10GB free; parallel workers that
     build or write large artifacts eat disk.
   - Pool size N: use the user's number, else default 8, always capped at
     the scope count (a small mission gets a small pool — never idle slots
     held against no work).

3. **Init the run dir and DB.** Never reuse a previous run's dir:
   ```sh
   S=~/.agents/scratch/$(basename "$PWD")-pool-$(shuf -i 100000-999999 -n 1)
   # fallback suffix: $(printf '%06d' $((RANDOM % 1000000)))
   mkdir -p "$S"
   "$DBCTL" init "$S/mission.db"
   "$DBCTL" event "$S/mission.db" pool-init "mission: <one line>, host clock fresh"
   ```
   Read the clock fresh at the moment of every write — never trust a date
   remembered from conversation context. `datetime('now')` inside SQL, or
   `date +%F\ %T` in shell for log lines.

4. **Partition into scopes.** Split the work items into scopes of ~5-15
   items each, cut along natural boundaries (directory, module, locale,
   ticket group) so one worker's edits never spill across scopes. No item
   appears in two scopes; if completing one scope turns out to require
   touching another scope's items, register a NEW scope carrying those
   items instead of reaching across. Every scope row carries its explicit
   item list via `scope-add`. Register the planned acceptance gate per
   scope in the protocol (step 5).

5. **Write MISSION_PROTOCOL.md in $S BEFORE spawning anyone.** Every worker
   prompt then reduces to the run dir, the scope name, and "read
   MISSION_PROTOCOL.md and follow it exactly" — small prompts, uniform
   discipline. The protocol must state:
   - Read the target project's binding rules file (AGENTS.md / CLAUDE.md
     or equivalent) if one exists, and follow it.
   - Claim the scope with `scope-claim <db> <scope> <your agent id>`;
     complete it with `scope-done` (or `scope-fail` with a reason).
   - The mission's done criteria, per scope, in measurable terms.
   - Smallest correct change per the project's own style; no unrelated
     edits; no new features; never touch items outside the scope's list.
   - For each work item the worker cannot honestly complete: `task-add`
     with detail, or record the blocker in the scope note — reporting a
     blocker is a valid completion, silent skipping is not.
   - If the mission has a per-scope verification command (build, test,
     validator, lint), run it and be patient on any shared lock; retry
     once after ~60s when a failure is confined to another scope's
     in-flight items.
   - Clock discipline: stamp every DB write through the helper (it stamps
     automatically); never write a remembered date.
   - Never commit; never delete anything — unsolicited files move to
     `$S/orphans/` after their diff is saved ("park, never delete").

6. **Run the pool.** Spawn ONLY background subagents — never foreground,
   never a swarm-launcher. Record every spawned agent id: `scope-claim`
   takes it, and for spawn-before-claim record the id in an `event` row so
   the DB is the restart-safe agent↔scope map. Hold the pool at N; on every
   completion, read the output, cross-check the DB (a "completion" whose
   scope row did not advance is a stalled agent — resume it via its agent
   id), then refill the slot immediately. Prioritized refill: failed
   scopes needing redispatch first, pending scopes second. When every
   scope is `done` or terminally closed, the pool is finished.

7. **Recover, never redo.** Interrupted, failed, or turn-ended-early
   workers are resumed via `Agent(resume=<agent-id>)`; the DB is the source
   of truth — claims recorded `in_work` stay claimed, and a resumed worker
   redoes at most its last unobserved action. Log every resume in
   `events`. A worker that goes off-brief — editing items outside its
   scope, building unsolicited features — is a drift case, not a resume
   case: stop it through the harness's task-stop mechanism, and redispatch
   a FRESH agent carrying only the DB rows for that scope; never re-resume
   a drifted context.

8. **Out-of-band writer watch.** When a scope's gate keeps failing on
   items no scope owns, do not assume in-flight pool work: checksum-watch
   the tree twice ~45s apart
   (`find <tree> -type f -newermt <t0> | xargs md5sum`). If it still moves
   with no active pool task, inspect the process table for writers outside
   the harness's task list. Stopping a foreign process is user-mediated:
   confirm with the user first when it could be a live session they are
   using, then park (move, never delete) rogue files into `$S/orphans/`
   after saving a per-file diff.

9. **Final verification.** Run the mission's acceptance gate with the exit
   code captured explicitly — piping to `tail` masks it:
   ```sh
   <gate> > "$S/final.log" 2>&1; echo EXIT=$?
   ```
   Code missions: the project's own build/test suite. Non-code missions:
   the validator, spot-check pass, or review the mission defined at
   intake. A gate that cannot run is a red exit, never a silent pass. A
   linker/signal/Bus-error failure is environment-first: check disk
   (`df -h`) before suspecting the work.

10. **Report.** Deliver the consolidated report: a per-scope completion
    table, every recorded task with its resolution, the failure/wontfix
    rationales, anything left open for the user, and `$S/mission.db` as the
    complete ledger. Recommend a next step (APPROVE / RE-RUN OPEN SCOPES /
    NEEDS DECISIONS).

11. **Commit only on explicit request.** Conventional commits, explicit
    paths only (never stage-all), deletions and new files staged
    deliberately, never push unasked.

## Guardrails

- Pool members are background subagents only.
- The orchestrator never modifies work products; only scoped workers do.
- Workers never commit; commits happen only on the user's word.
- Every claim, completion, and failure transitions through a DB status —
   anything not in the DB did not happen.
- A scope's items are never touched by another scope's worker;
   cross-boundary work becomes a new registered scope.
- Park, never delete.
- Report-only mode stops after reporting; acting never starts unasked.
- The run dir and DB are scratch state — safe to inspect, never part of
   the target project.

## Degraded mode (no sqlite3)

Without `sqlite3`, the same discipline runs on plain files in the run dir:
`$S/scopes/<name>.status` (one of `pending|in_work|done|failed`) plus
`$S/scopes/<name>.items` and `$S/scopes/<name>.agent`, and an append-only
`$S/events.log` (`date +%F\ %T` prefix per line). File writes are atomic via
`mv` of a temp file. Everything else — partitioning, protocol, pool
discipline, recovery, final gate — is unchanged. Upgrade to the sqlite
helper when the tool becomes available; do not migrate a live run midway.

*Adapted from the pooled-review and pooled-codescene pool engines
(scopes/DB/protocol/resume mechanics), generalized to any mission.*
