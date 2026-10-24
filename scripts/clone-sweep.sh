#!/usr/bin/env bash
# One deterministic clone sweep: every scanned repo, cloned fresh, in
# parallel, with the method ladder inline.
# Usage: clone-sweep.sh [out-dir]
# Writes clone-outcomes.txt and the .sweep-done marker.
#
# The AI never clones: this is pure git and curl I/O. Each repo tries
# sparse, then full, then tarball, and records the outcome it reached.
# A repo that never populates is recorded blocked with its reason - an
# exception, never a reason to stop the sweep, and never silent. Auth
# rides the environment only: GH_TOKEN never enters argv, a log line,
# or any file.
set -uo pipefail

OUT="${1:-run-ledger/prepare}"
LIST="${REPO_LIST:-config/repo-list.txt}"
SOURCES="${SOURCES_DIR:-sources}"
JOBS="${CLONE_JOBS:-8}"
SCOPE_TRUTH="${SCOPE_TRUTH_REPO:-storytold/craft-libs}"
SCOPE_TRUTH_PATHS="${SCOPE_TRUTH_PATHS:-AGENTS.md,Cargo.toml,crates,docs,licenses}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$OUT"
outcomes="$OUT/clone-outcomes.txt"
: > "$outcomes"
export GIT_TERMINAL_PROMPT=0
umask 077

# The configured repos as "<owner/repo> <watch-paths csv>" records.
items() {
  sed -e 's/#.*$//' "$LIST" \
    | awk 'NF >= 3 { print $1 "\t" $3 }'
}

# One repo's ladder: sparse, then full, then tarball. Appends exactly
# one outcome line, whatever the outcome is.
clone_one() {
  local repo="$1" paths="$2" slug method sha files
  slug="${repo##*/}"
  if [ "$repo" = "$SCOPE_TRUTH" ]; then slug="craft-libs"; fi
  local dest="$SOURCES/$slug"

  for method in sparse full tarball; do
    rm -rf "$dest"
    if [ "$method" = sparse ]; then
      # shellcheck disable=SC2046
      bash "$SCRIPT_DIR/clone-sources.sh" sparse "$repo" "$dest" \
        $(printf '%s' "$paths" | tr ',' ' ') >/dev/null 2>&1
    elif [ "$method" = full ]; then
      bash "$SCRIPT_DIR/clone-sources.sh" full "$repo" "$dest" >/dev/null 2>&1
    else
      bash "$SCRIPT_DIR/clone-sources.sh" tarball "$repo" "$dest" >/dev/null 2>&1
    fi
    if [ "$?" -eq 0 ]; then
      files="$(find "$dest" -type f 2>/dev/null | wc -l)"
      sha="$(git -C "$dest" rev-parse --short HEAD 2>/dev/null || true)"
      if [ -z "$sha" ]; then
        printf '%s\tok-degraded\t%s\tno-rev\t%s\n' \
          "$repo" "$method" "$files" >> "$outcomes"
      else
        printf '%s\tok\t%s\t%s\t%s\n' "$repo" "$method" "$sha" "$files" >> "$outcomes"
      fi
      return 0
    fi
  done

  rm -rf "$dest"
  printf '%s\tblocked\tall-methods-failed\t-\t0\n' "$repo" >> "$outcomes"
  return 0
}

# The full item set: every configured repo, plus scope truth.
{
  items
  printf '%s\tscope-truth\t%s\n' "$SCOPE_TRUTH" "$SCOPE_TRUTH_PATHS"
} > "$OUT/sweep-items.tsv"

# Every repo's ladder runs in parallel, bounded by CLONE_JOBS. One
# repo's failure never delays another repo's attempt.
running=0
while IFS=$'\t' read -r repo purpose paths; do
  [ -n "${repo:-}" ] || continue
  clone_one "$repo" "$paths" &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then
    wait -n 2>/dev/null || wait
    running=$((running - 1))
  fi
done < "$OUT/sweep-items.tsv"
wait

sort -o "$outcomes" "$outcomes"
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/.sweep-done"
cat "$outcomes"
