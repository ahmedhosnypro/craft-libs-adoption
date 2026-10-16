#!/usr/bin/env bash
# Deterministic half of the skill's authoring gate; run before every push.
# Bash + python3 + grep only — the Bun-dependent checks live in the repo
# AGENTS.md validation section.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
fail=0
ck() { if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fail=1; fi }

python3 - "$SKILL" << 'PY'
import os
import re
import sys
try:
    import yaml
except Exception as e:
    print(f"FAIL: pyyaml unavailable: {e}"); sys.exit(1)
try:
    d = yaml.safe_load(open(sys.argv[1]).read().split('---')[1])
except Exception as e:
    print(f"FAIL: frontmatter YAML parse: {e}"); sys.exit(1)
name = os.path.basename(os.path.dirname(os.path.abspath(sys.argv[1])))
ok = d.get('name') == name
print("PASS: frontmatter YAML parses" if ok else f"FAIL: name {d.get('name')} != dir {name}")
if not ok: sys.exit(1)
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', str(d.get('version', ''))):
    print(f"FAIL: version {d.get('version')!r} is not semver"); sys.exit(1)
if 'description' not in d or 'Use' not in str(d['description']):
    print("FAIL: description must exist and carry trigger conditions"); sys.exit(1)
print(f"PASS: version {d.get('version')} + trigger-condition description present")
PY
[ $? -ne 0 ] && fail=1

n_amd=$(grep -c '^## Amendment' "$SKILL")
[ "$n_amd" -eq 0 ] && echo "PASS: no amendment blocks (current-state law only)" \
  || { echo "FAIL: $n_amd amendment block(s) present"; fail=1; }

n_sk=$(wc -l < "$SKILL")
[ "$n_sk" -lt 500 ] && echo "PASS: SKILL.md is $n_sk lines (< 500)" \
  || { echo "FAIL: SKILL.md is $n_sk lines (>= 500)"; fail=1; }

for ref in "$DIR"/references/*.md; do
  n=$(wc -l < "$ref")
  [ "$n" -lt 300 ] && echo "PASS: $(basename "$ref") is $n lines (< 300)" \
    || { echo "FAIL: $(basename "$ref") is $n lines (>= 300)"; fail=1; }
done

for ref in $(grep -oE 'references/[a-z0-9-]+\.md' "$SKILL" | sort -u); do
  if [ -f "$DIR/$ref" ]; then echo "PASS: SKILL.md link $ref exists"; else echo "FAIL: SKILL.md links missing $ref"; fail=1; fi
done

# No calendar dates in prose. Fenced code blocks are exempt: sample data
# inside diagram examples (e.g. gantt start dates) is syntax demonstration,
# not chronology. Legal files (LICENSE) live outside the skill dir.
prose="$(mktemp)"
trap 'rm -f "$prose"' EXIT
find "$DIR" -type f \( -name '*.md' -o -name '*.ts' -o -name '*.sh' -o -name '*.yaml' -o -name '*.json' \) ! -name 'verify_skill.sh' \
  -exec awk '/^```/ { fence = !fence; next } !fence { print FILENAME ":" FNR "\t" $0 }' {} + > "$prose"
date_leaks=$(grep -E '\b20[0-9]{2}-[01][0-9]-[0-3][0-9]\b' "$prose")
if [ -n "$date_leaks" ]; then echo "FAIL: calendar date in prose:"; echo "$date_leaks"; fail=1; else echo "PASS: no calendar dates in prose"; fi

# Privacy gate: no absolute local home paths in committed skill files.
# (/home/<user> placeholders are the sanctioned form.)
leaks=$(grep -rInE '/home/[A-Za-z0-9_.-]+/' "$DIR" \
  --include='*.md' --include='*.ts' --include='*.sh' \
  --include='*.yaml' --include='*.json' 2>/dev/null \
  | grep -vF '/home/<user>' | grep -v 'verify_skill.sh')
[ -z "$leaks" ] && echo "PASS: no absolute local home paths" \
  || { echo "FAIL: local user path leak:"; echo "$leaks"; fail=1; }

# No personal home-layout paths: ~/<dir> names a user's own tree;
# ~/.<dir> standard locations are sanctioned.
tilde_leaks=$(grep -rInE '~/[A-Za-z0-9]' "$DIR" \
  --include='*.md' --include='*.ts' --include='*.sh' \
  --include='*.yaml' --include='*.json' 2>/dev/null \
  | grep -v 'verify_skill.sh')
[ -z "$tilde_leaks" ] && echo "PASS: no personal home-layout paths" \
  || { echo "FAIL: personal home-layout path leak:"; echo "$tilde_leaks"; fail=1; }

exit $fail
