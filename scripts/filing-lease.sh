#!/usr/bin/env bash
# Filing lease: the mission files at most 3 findings and 3 bump PRs per
# window. Independent PR pipelines take a lease before any GitHub
# write, so the cap holds without a window-wide ranking barrier.
# flock serializes the count; an over-cap slug defers and records why.
set -euo pipefail

KIND="${1:?usage: filing-lease.sh <finding|bump> <slug>}"
SLUG="${2:?usage: filing-lease.sh <finding|bump> <slug>}"
case "$KIND" in
  finding | bump) ;;
  *) echo "usage: filing-lease.sh <finding|bump> <slug>" >&2; exit 2 ;;
esac

CAP="${CRAFT_FILING_CAP:-3}"
LEDGER="run-ledger/filing"
LEASE="$LEDGER/$KIND.lease"

mkdir -p "$LEDGER"
exec 9>"$LEDGER/$KIND.lock"
flock 9

if [ -f "$LEASE" ] && grep -Fxq "$SLUG" "$LEASE"; then
  # The slug's own retry keeps its slot; the cap counts slugs.
  echo "leased (slot held by $SLUG)"
  exit 0
fi

taken=0
if [ -f "$LEASE" ]; then
  taken="$(grep -c . "$LEASE" || true)"
fi
if [ "$taken" -ge "$CAP" ]; then
  echo "over-cap: $taken of $CAP $KIND leases taken this window; $SLUG defers"
  exit 1
fi

printf '%s\n' "$SLUG" >> "$LEASE"
echo "leased slot $((taken + 1)) of $CAP for $SLUG"
exit 0
