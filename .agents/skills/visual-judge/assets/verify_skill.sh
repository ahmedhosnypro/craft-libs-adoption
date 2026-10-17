#!/usr/bin/env bash
# Deterministic authoring gate for visual-judge. Run before every push.
# Bash + python3 + grep only.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
fail=0
ck() { if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fail=1; fi }

python3 - "$SKILL" << 'PY'
import os, re, sys
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
print(f"PASS: version {d['version']} + trigger-condition description present")
PY
[ $? -ne 0 ] && fail=1

# Prose with fenced code blocks stripped (their contents are data/demos).
prose="$(mktemp)"; trap 'rm -f "$prose"' EXIT
find "$DIR" -type f -name '*.md' \
  -exec awk '/^```/ { fence = !fence; next } !fence { print FILENAME ":" FNR "\t" $0 }' {} + > "$prose"

# Description carries negative scope.
grep -q 'Do NOT use' "$SKILL"
ck $? "description carries explicit negative scope"

# Current-state law only: no amendment blocks, no change-history narrative.
! grep -En '^## (Amendment|Change history|History)' "$SKILL" >/dev/null
ck $? "no amendment/history blocks (current-state law only)"

# Structural caps.
n_sk=$(wc -l < "$SKILL")
[ "$n_sk" -lt 500 ] && echo "PASS: SKILL.md is $n_sk lines (< 500)" \
  || { echo "FAIL: SKILL.md is $n_sk lines (>= 500)"; fail=1; }
for rf in "$DIR"/references/*.md; do
  [ -e "$rf" ] || continue
  n=$(wc -l < "$rf")
  [ "$n" -lt 300 ] && echo "PASS: references/$(basename "$rf") is $n lines (< 300)" \
    || { echo "FAIL: references/$(basename "$rf") is $n lines (>= 300)"; fail=1; }
done

# No calendar dates anywhere in skill prose.
! grep -E '\b20[0-9]{2}-[01][0-9]-[0-3][0-9]\b' "$prose" >/dev/null
ck $? "no calendar dates in prose"

# No local user paths (sanctioned form is /home/<user> or ~).
leaks=$(grep -rInE '/home/[A-Za-z0-9_.-]+/' "$DIR" \
  --include='*.md' --include='*.sh' \
  | grep -vF '/home/<user>' | grep -v 'verify_skill.sh')
[ -z "$leaks" ] && echo "PASS: no personal user paths" \
  || { echo "FAIL: personal user path leak:"; echo "$leaks"; fail=1; }

# No privileged or system-mutating command text.
! grep -inE '(^|[^a-z])(sudo|killall|pkill)([^a-z]|$)' "$prose" >/dev/null
ck $? "no sudo/kill command text"
! grep -inE '\b(curl|wget)[[:space:]]' "$prose" >/dev/null
ck $? "no download command text"
! grep -inE '[^a-z]kill[[:space:]]|-9[[:space:]]' "$prose" >/dev/null
ck $? "no process-kill recipes"

exit $fail
