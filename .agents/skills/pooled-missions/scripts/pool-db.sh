#!/usr/bin/env bash
# Tracking-DB helper for the pooled-missions skill.
# sqlite3 + coreutils only. Every write stamps datetime('now') server-side.
set -u

usage() {
  cat <<'EOF'
usage: pool-db.sh <command> <db> [args]

commands:
  init <db>                        create schema (idempotent)
  scope-add <db> <name> <items>    register scope (items: csv list)
  scope-list <db> [status]         list scopes (all, or filtered)
  scope-claim <db> <name> <agent>  pending -> in_work, record agent
  scope-done <db> <name> [note]    in_work -> done
  scope-fail <db> <name> <reason>  in_work -> failed
  task-add <db> <scope> <item> [detail]
  task-done <db> <id> [note]
  task-wontfix <db> <id> <reason>
  event <db> <kind> <detail>       append to run ledger
  status <db>                      dashboard: counts, clock, oldest active row
EOF
  exit 2
}

die() { echo "pool-db.sh: $*" >&2; exit 1; }
need_sqlite() { command -v sqlite3 >/dev/null 2>&1 \
  || die "sqlite3 not found. Install it, or run the skill's degraded (plain-file) mode."; }
need_db() { [ -n "${DB:-}" ] && [ -f "$DB" ] || die "db '$DB' does not exist; run 'init' first"; }

# Escape single quotes for SQL string literals.
sq() { printf '%s' "$1" | sed "s/'/''/g"; }

run() { sqlite3 -cmd ".timeout 15000" -batch "$DB" "$1"; }

CMD="${1:-}"; DB="${2:-}"; [ -n "$CMD" ] && [ -n "$DB" ] || usage
shift 2 || true

case "$CMD" in
  init)
    need_sqlite
    mkdir -p "$(dirname "$DB")"
    sqlite3 -cmd ".timeout 15000" -batch "$DB" <<'EOF' >/dev/null
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS scopes(
  name TEXT PRIMARY KEY,
  items TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_work','done','failed')),
  agent TEXT, note TEXT,
  updated_at TEXT DEFAULT (datetime('now')));
CREATE TABLE IF NOT EXISTS tasks(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope TEXT NOT NULL, item TEXT NOT NULL, detail TEXT,
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','done','wontfix')),
  note TEXT,
  updated_at TEXT DEFAULT (datetime('now')));
CREATE TABLE IF NOT EXISTS events(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT DEFAULT (datetime('now')), kind TEXT, detail TEXT);
EOF
    ;;
  scope-add)
    need_sqlite; need_db; NAME="${1:-}"; ITEMS="${2:-}"
    [ -n "$NAME" ] && [ -n "$ITEMS" ] || usage
    run "INSERT OR REPLACE INTO scopes(name, items, status, updated_at)
         VALUES('$(sq "$NAME")', '$(sq "$ITEMS")', 'pending', datetime('now'));"
    ;;
  scope-list)
    need_sqlite; need_db
    if [ $# -ge 1 ]; then
      run "SELECT name || ' | ' || status || ' | ' || COALESCE(agent,'') || ' | ' || items
           FROM scopes WHERE status = '$(sq "$1")' ORDER BY name;"
    else
      run "SELECT name || ' | ' || status || ' | ' || COALESCE(agent,'') || ' | ' || items
           FROM scopes ORDER BY name;"
    fi
    ;;
  scope-claim)
    need_sqlite; need_db; NAME="${1:-}"; AGENT="${2:-}"
    [ -n "$NAME" ] && [ -n "$AGENT" ] || usage
    run "UPDATE scopes SET status='in_work', agent='$(sq "$AGENT")',
           updated_at=datetime('now')
         WHERE name='$(sq "$NAME")' AND status='pending';
         SELECT changes();"
    ;;
  scope-done)
    need_sqlite; need_db; NAME="${1:-}"; NOTE="${2:-}"
    [ -n "$NAME" ] || usage
    run "UPDATE scopes SET status='done',
           note=COALESCE(NULLIF('$(sq "$NOTE")',''), note),
           updated_at=datetime('now')
         WHERE name='$(sq "$NAME")' AND status='in_work';
         SELECT changes();"
    ;;
  scope-fail)
    need_sqlite; need_db; NAME="${1:-}"; REASON="${2:-}"
    [ -n "$NAME" ] && [ -n "$REASON" ] || usage
    run "UPDATE scopes SET status='failed', note='$(sq "$REASON")',
           updated_at=datetime('now')
         WHERE name='$(sq "$NAME")';
         SELECT changes();"
    ;;
  task-add)
    need_sqlite; need_db; SCOPE="${1:-}"; ITEM="${2:-}"; DETAIL="${3:-}"
    [ -n "$SCOPE" ] && [ -n "$ITEM" ] || usage
    run "INSERT INTO tasks(scope, item, detail, updated_at)
         VALUES('$(sq "$SCOPE")', '$(sq "$ITEM")', NULLIF('$(sq "$DETAIL")',''),
                datetime('now'));
         SELECT last_insert_rowid();"
    ;;
  task-done)
    need_sqlite; need_db; ID="${1:-}"; NOTE="${2:-}"
    [ -n "$ID" ] || usage
    run "UPDATE tasks SET status='done',
           note=NULLIF('$(sq "$NOTE")',''), updated_at=datetime('now')
         WHERE id=$ID; SELECT changes();"
    ;;
  task-wontfix)
    need_sqlite; need_db; ID="${1:-}"; REASON="${2:-}"
    [ -n "$ID" ] && [ -n "$REASON" ] || usage
    run "UPDATE tasks SET status='wontfix', note='$(sq "$REASON")',
           updated_at=datetime('now')
         WHERE id=$ID; SELECT changes();"
    ;;
  event)
    need_sqlite; need_db; KIND="${1:-}"; DETAIL="${2:-}"
    [ -n "$KIND" ] || usage
    run "INSERT INTO events(kind, detail)
         VALUES('$(sq "$KIND")', NULLIF('$(sq "$DETAIL")',''));"
    ;;
  status)
    need_sqlite; need_db
    run "SELECT 'clock ' || datetime('now');"
    run "SELECT 'scopes ' || status || ' ' || COUNT(*)
         FROM scopes GROUP BY status ORDER BY status;"
    run "SELECT 'tasks ' || status || ' ' || COUNT(*)
         FROM tasks GROUP BY status ORDER BY status;"
    run "SELECT 'oldest_active ' || MIN(updated_at)
         FROM scopes WHERE status IN ('pending','in_work');"
    ;;
  *) usage ;;
esac
