#!/usr/bin/env bash
# Launches the run's three independent sweeps in parallel and reports
# their progress. The sweeps overlap: the window collection, the clone
# sweep, and the verdict-digest read are independent I/O, and the
# oracle's wall time is their MAX, not their sum.
# Usage: launch-sweeps.sh <since-iso> [out-dir]
#
# The caller polls the markers the sweeps write; this script only
# starts the work and returns. It is safe to call twice: each sweep
# writes its own marker on completion and a second launch of a
# finished sweep is a no-op the caller skips.
set -uo pipefail

SINCE="${1:?since ISO-8601 timestamp required}"
OUT="${2:-run-ledger/prepare}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR="$ROOT/scripts"

mkdir -p "$OUT/logs"

# Already-finished sweeps are skipped: markers are the idempotence key.
if [ ! -f "$OUT/.collect-done" ]; then
  nohup bash "$SCRIPT_DIR/collect-window.sh" "$SINCE" "$OUT" \
    > "$OUT/logs/collect.log" 2>&1 &
  echo "launched collect pid=$!"
fi

if [ ! -f "$OUT/.sweep-done" ]; then
  nohup bash "$SCRIPT_DIR/clone-sweep.sh" "$OUT" \
    > "$OUT/logs/sweep.log" 2>&1 &
  echo "launched sweep pid=$!"
fi

if [ ! -f "$OUT/.digest-done" ]; then
  nohup bash "$SCRIPT_DIR/verdict-digest.sh" "$OUT" \
    > "$OUT/logs/digest.log" 2>&1 &
  echo "launched digest pid=$!"
fi

echo "markers:"
for m in .collect-done .sweep-done .digest-done; do
  if [ -f "$OUT/$m" ]; then
    echo "  $m done at $(cat "$OUT/$m")"
  else
    echo "  $m pending"
  fi
done
