#!/usr/bin/env bash
# Deterministic watch-path pre-filter over the collected window rows.
# Usage: prefilter.sh <out-dir>
# Writes <out-dir>/prefilter.jsonl, prefilter.md, and .prefilter-done.
#
# For every PR in rows.jsonl this fetches the changed-file list (GET
# only) and intersects it with the repo's watch-paths — the
# classifier's first rule, computed in bash. A PR whose files hit no
# watch-path and carry no pin file is a scripted `irrelevant`: the
# workflow records it without a pipeline. A file-list gap, a page cap,
# or a pin file is never skipped — those PRs always get pipelines.
set -uo pipefail

OUT="${1:?out-dir required}"
LIST="${REPO_LIST:-config/repo-list.txt}"
PAGE_CAP="${PAGE_CAP:-3}"

rows="$OUT/rows.jsonl"
if [ ! -s "$rows" ]; then
  echo "prefilter: no rows.jsonl in $OUT" >&2
  date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/.prefilter-done"
  exit 0
fi
out="$OUT/prefilter.jsonl"
: > "$out"

# watch-paths csv per repo: column 3 of repo-list.txt (comments skip).
wp_for() {
  awk -v r="$1" '!/^[[:space:]]*#/ && NF >= 3 && $1 == r { print $3; exit }' "$LIST"
}

skipped=0
pipelined=0
errors=0
while IFS= read -r row; do
  [ -z "$row" ] && continue
  repo=$(printf '%s' "$row" | jq -r '.repo' 2>/dev/null) || repo=""
  num=$(printf '%s' "$row" | jq -r '.number' 2>/dev/null) || num=""
  if [ -z "$repo" ] || [ -z "$num" ]; then
    errors=$((errors + 1))
    continue
  fi

  # The changed-file list, capped at PAGE_CAP pages of 100.
  names=""
  files_n=0
  truncated=0
  err=""
  page=1
  while [ "$page" -le "$PAGE_CAP" ]; do
    body="$(gh api "repos/$repo/pulls/$num/files?per_page=100&page=$page" 2>/dev/null)" || {
      err="fetch"
      break
    }
    page_names="$(printf '%s' "$body" | jq -r '.[].filename' 2>/dev/null)" || {
      err="parse"
      break
    }
    count=$(printf '%s\n' "$page_names" | grep -c . || true)
    files_n=$((files_n + count))
    [ -n "$names" ] && page_names="$(printf '%s\n%s' "$names" "$page_names")"
    names="$page_names"
    if [ "$count" -lt 100 ]; then break; fi
    if [ "$page" -eq "$PAGE_CAP" ]; then truncated=1; fi
    page=$((page + 1))
  done

  matched=""
  pin=0
  if [ -z "$err" ]; then
    wp="$(wp_for "$repo")"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      base="${f##*/}"
      if [ "$base" = "Cargo.lock" ] || [ "$base" = "Cargo.toml" ]; then
        pin=1
      fi
      IFS=',' read -ra wps <<< "$wp"
      for wp_ in "${wps[@]}"; do
        wp_="$(printf '%s' "$wp_" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$wp_" ] && continue
        case "$f" in
          "$wp_"|"$wp_"/*) matched="$matched$f"$'\n'; break ;;
        esac
      done
    done <<< "$names"
  fi
  if [ -n "$(printf '%s' "$matched" | grep .)" ] || [ "$pin" -eq 1 ] || [ -n "$err" ] || [ "$truncated" -eq 1 ]; then
    intersect=true
    pipelined=$((pipelined + 1))
  else
    intersect=false
    skipped=$((skipped + 1))
  fi

  matched_json="$(printf '%s' "$matched" | grep . | head -10 | jq -Rs 'split("\n") | map(select(length > 0))' 2>/dev/null)" \
    || matched_json="[]"
  [ -n "$matched_json" ] || matched_json="[]"
  jq -cn \
    --arg repo "$repo" --argjson number "$num" \
    --argjson files_n "$files_n" --argjson truncated "$truncated" \
    --argjson pin "$pin" --argjson intersect "$intersect" \
    --arg error "${err:-}" \
    --argjson matched "$matched_json" \
    '{repo: $repo, number: $number, files_n: $files_n, truncated: $truncated,
      pin: $pin, intersect: $intersect, error: $error, matched: $matched}' >> "$out"
  sleep 0.15
done < "$rows"

errors=$(grep -c '"error":"[a-z]' "$out" 2>/dev/null || true)
{
  echo "# Watch-path pre-filter"
  echo
  echo "- rows: $(wc -l < "$rows")"
  echo "- pipelined (intersect, pin, truncated, or error): $pipelined"
  echo "- scripted irrelevant (no pipeline): $skipped"
  echo "- file-list errors: $errors"
} > "$OUT/prefilter.md"
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/.prefilter-done"
cat "$OUT/prefilter.md"
