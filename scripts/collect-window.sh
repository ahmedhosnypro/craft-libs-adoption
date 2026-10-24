#!/usr/bin/env bash
# One deterministic REST sweep of the adoption scan's window.
# Usage: collect-window.sh <since-iso> [out-dir]
# Writes rows.jsonl, collection.md, and the .collect-done marker.
#
# The AI never collects the window: this is pure I/O over gh's default
# GET. Nothing here decides anything - it records facts, and every fact
# it cannot establish is a named marker, never a guess.
set -uo pipefail

SINCE="${1:?since ISO-8601 timestamp required}"
OUT="${2:-run-ledger/prepare}"
LIST="${REPO_LIST:-config/repo-list.txt}"
PAGE_CAP="${PAGE_CAP:-15}"
WINDOW="${WINDOW:-7h}"

mkdir -p "$OUT"
rows="$OUT/rows.jsonl"
: > "$rows"
rm -f "$OUT/per-repo.tsv"
markers=()

# The configured repos, owner/name per line: comments and blanks skip.
repos() {
  sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$LIST" \
    | awk 'NF >= 2 { print $1 }'
}

total=0
for repo in $(repos); do
  keep=0
  page=1
  truncated=0
  while [ "$page" -le "$PAGE_CAP" ]; do
    body="$(
      gh api --method GET \
        "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=$page" \
        2>/dev/null
    )" || { markers+=("collection-error:$repo:page-$page"); break; }

    newest=$(printf '%s' "$body" | jq -r '[.[].updated_at] | max // ""' 2>/dev/null)
    kept=$(printf '%s' "$body" | jq -c --arg since "$SINCE" --arg repo "$repo" '
      [ .[]
        | select(.merged_at != null and .merged_at >= $since)
        | {repo: $repo, number: .number, title: .title,
           merged_at: .merged_at, user: (.user.login // ""),
           html_url: .html_url}
      ]' 2>/dev/null) || { markers+=("collection-error:$repo:page-$page:parse"); break; }

    n=$(printf '%s' "$kept" | jq 'length' 2>/dev/null || echo 0)
    if [ "$n" -gt 0 ]; then
      printf '%s\n' "$kept" | jq -c '.[]' >> "$rows"
    fi
    keep=$((keep + n))
    total=$((total + n))

    # An empty page, or a page whose newest update predates the
    # window, ends this repo's paging.
    if [ -z "$body" ] || [ "$body" = "[]" ]; then break; fi
    if [ -n "$newest" ] && [[ "$newest" < "$SINCE" ]]; then break; fi
    page=$((page + 1))
  done

  if [ "$page" -gt "$PAGE_CAP" ]; then
    truncated=1
    markers+=("collection-truncated:$repo:page-cap-$PAGE_CAP")
  fi
  printf '%s\t%s\t%s\n' "$repo" "$keep" "$truncated" >> "$OUT/per-repo.tsv"
done

# The helper cross-check: REST is the record, the helper is the audit.
# A mismatch is an exception the window comment names.
help="$OUT/prs.json"
if command -v craft-helpers >/dev/null 2>&1; then
  craft-helpers prs --org storytold --repos "$(repos | paste -sd, -)" \
    --since "$WINDOW" --limit-per-repo 100 --json > "$help" 2>/dev/null \
    || markers+=("helper-unavailable")
else
  markers+=("helper-unavailable")
fi

{
  echo "# Window collection"
  echo
  echo "- since: $SINCE"
  echo "- rows: $total"
  echo "- repos: $(repos | wc -l)"
  echo
  echo "## Per-repo merged counts"
  echo
  echo "| repo | merged | truncated |"
  echo "|---|---|---|"
  if [ -f "$OUT/per-repo.tsv" ]; then
    sort -t"$(printf '\t')" -k2 -nr "$OUT/per-repo.tsv" \
      | awk -F'\t' '{print "| " $1 " | " $2 " | " $3 " |"}'
  fi
  echo
  if [ "${#markers[@]}" -gt 0 ]; then
    echo "## Markers (exceptions)"
    echo
    for m in "${markers[@]}"; do echo "- $m"; done
  else
    echo "## Markers"
    echo
    echo "- none"
  fi
} > "$OUT/collection.md"

date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/.collect-done"
cat "$OUT/collection.md"
