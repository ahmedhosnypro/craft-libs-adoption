#!/usr/bin/env bash
# The run-start state read, deterministically: the maintainer-verdict
# digest from the tracking issue on the target repo.
# Usage: verdict-digest.sh [out-dir]
# Writes digest.md and the .digest-done marker.
#
# Read-only, GET only. Without the digest a candidate closed with
# revival conditions gets re-filed every window, so this is not
# optional; but it is pure API reads, never a reason to block the
# sweep - a tracking issue that does not exist yet is a recorded gap,
# not a failure.
set -uo pipefail

OUT="${1:-run-ledger/prepare}"
REPO="${TARGET_REPO:-ahmedhosnypro/craft-libs}"
SEARCH="${DIGEST_SEARCH:-adoption-scan in:title}"

mkdir -p "$OUT"
digest="$OUT/digest.md"
: > "$digest"

# The tracking issue's current body: the run's starting state.
body="$OUT/prior-state.md"
if ! gh issue list --repo "$REPO" --state all --search 'Adoption scan rollups' \
     --json number,title,body,state,url --limit 1 > "$OUT/tracking.json" 2>/dev/null; then
  {
    echo "# Maintainer-verdict digest"
    echo
    echo "- gap: the tracking issue could not be read ($REPO); the prior state is empty"
  } > "$digest"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/.digest-done"
  cat "$digest"
  exit 0
fi

jq -r '.[0].body // ""' "$OUT/tracking.json" > "$body"
issue_url="$(jq -r '.[0].url // ""' "$OUT/tracking.json")"

# Closed findings, each one's latest pre-closeAt verdict comment.
closed_json="$OUT/closed-findings.json"
if ! gh issue list --repo "$REPO" --state closed --search "$SEARCH" \
     --json number,title,closedAt --limit 50 > "$closed_json" 2>/dev/null; then
  closed_json=""
fi

{
  echo "# Maintainer-verdict digest"
  echo
  echo "- tracking issue: $issue_url"
  echo "- prior state bytes: $(wc -c < "$body" | tr -d ' ')"
  echo
  echo "| finding | slug | verdict | unmet conditions |"
  echo "|---|---|---|---|"
} > "$digest"

if [ -s "${closed_json:-/dev/null}" ]; then
  count="$(jq 'length' "$closed_json")"
  i=0
  while [ "$i" -lt "$count" ]; do
    number="$(jq -r ".[$i].number" "$closed_json")"
    title="$(jq -r ".[$i].title" "$closed_json")"
    closed_at="$(jq -r ".[$i].closedAt" "$closed_json")"
    slug="$(printf '%s' "$title" | sed -e 's/^adoption-scan:[[:space:]]*//')"

    # The latest comment created before closeAt carrying a Verdict or
    # Resolution heading; no author check.
    verdict="$(
      gh api "repos/$REPO/issues/$number/comments" --paginate 2>/dev/null \
        | jq -r --arg before "$closed_at" '
            [ .[]
              | select((.created_at // "") <= $before)
              | select((.body // "") | test("(?i)^#{0,3}[[:space:]]*(verdict|resolution)"))
            ] | last | .body // ""
          ' 2>/dev/null | head -c 2000
    )"

    if [ -z "$verdict" ]; then
      verdict_line="closed without recorded verdict"
    else
      verdict_line="$(printf '%s' "$verdict" | tr '\n' ' ' | tr -s ' ' | head -c 400)"
    fi

    printf '| %s | %s | %s | |\n' "$number" "$slug" "$verdict_line" >> "$digest"
    i=$((i + 1))
  done
else
  echo "| - | no closed findings listed | gap: the closed-findings read failed or the list is empty | |" \
    >> "$digest"
fi

date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT/.digest-done"
cat "$digest"
