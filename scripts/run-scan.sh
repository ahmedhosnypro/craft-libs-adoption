#!/usr/bin/env bash
# Runs the adoption scan with the live stream renderer attached.
# Self-contained on purpose: the composite action funnels the binary's
# stdout into the transcript file, so nothing reaches the job log while a
# run is alive; this wrapper installs the same release binaries, runs the
# scan, and renders the stream into the log turn by turn.
set -euo pipefail

VERSION="${CRAFT_AGENT_VERSION:-v0.0.15}"
REPO="${CRAFT_AGENT_RELEASE_REPOSITORY:-ahmedhosnypro/craft-agent}"

case "${RUNNER_OS}:${RUNNER_ARCH}" in
  Linux:X64) triple="x86_64-unknown-linux-musl" ;;
  Linux:ARM64) triple="aarch64-unknown-linux-musl" ;;
  *)
    echo "::error::unsupported runner ${RUNNER_OS}/${RUNNER_ARCH} — the release ships Linux x86_64 and aarch64 binaries"
    exit 1
    ;;
esac
base="https://github.com/${REPO}/releases/download/${VERSION}"
dir="${RUNNER_TEMP}/craft-agent-download"
rm -rf "$dir"
mkdir -p "$dir"
curl -fsSL -o "${dir}/checksums.txt" "${base}/checksums.txt"
agent_asset="$(awk -v asset="craft-agent-${triple}" '$2 == asset || $2 ~ ("/" asset "$") { print $2; exit }' "${dir}/checksums.txt")"
helpers_asset="$(awk -v asset="craft-helpers-${triple}" '$2 == asset || $2 ~ ("/" asset "$") { print $2; exit }' "${dir}/checksums.txt")"
if [ -z "$agent_asset" ] || [ -z "$helpers_asset" ]; then
  echo "::error::no checksums.txt entry for craft-agent/craft-helpers ${triple} in release ${VERSION}"
  exit 1
fi
mkdir -p "${dir}/$(dirname "$agent_asset")" "${dir}/$(dirname "$helpers_asset")"
curl -fsSL -o "${dir}/${agent_asset}" "${base}/craft-agent-${triple}"
curl -fsSL -o "${dir}/${helpers_asset}" "${base}/craft-helpers-${triple}"
(cd "$dir" && sha256sum --check checksums.txt --ignore-missing)
bindir="${RUNNER_TEMP}/craft-agent-bin"
mkdir -p "$bindir"
install -m 0755 "${dir}/${agent_asset}" "${bindir}/craft-agent"
install -m 0755 "${dir}/${helpers_asset}" "${bindir}/craft-helpers"
export PATH="${bindir}:${PATH}"
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$bindir" >> "$GITHUB_PATH"
fi

# Pre-flight: every agent profile must load in the engine before a run
# spends hours on it. A rejected profile fails the job here, in seconds.
shopt -s nullglob
for profile in "${GITHUB_WORKSPACE}"/.craft-agent/agents/*.md; do
  name="$(basename "$profile" .md)"
  out="$(echo hi | CRAFT_AGENT_PROVIDER=anthropic ANTHROPIC_API_KEY=dummy \
    CRAFT_AGENT_MODEL=dummy craft-agent run --agent "$name" \
    --prompt /dev/stdin --output-format plain 2>&1 || true)"
  if printf '%s' "$out" | grep -qE 'skipped agent file|agent file is invalid|MD0[0-9]|unknown agent profile|available: \(none found\)'; then
    echo "::error::agent profile '$name' failed engine validation: $(printf '%s' "$out" | grep -E 'MD0[0-9]|invalid|unknown agent profile|none found' | head -n 1)"
    exit 1
  fi
done

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git config --global user.name "craft-agent"
git config --global user.email "agent@craft-agent.invalid"

if [ -n "${GH_TOKEN:-}" ]; then
  # The write-repo gh gate must fail closed; the credential helper is
  # runner-wide, so plain git push would bypass it. An empty knob means
  # no gate, and the helper is installed.
  if [ -z "${CRAFT_AGENT_WRITE_REPO:-}" ]; then
    gh auth setup-git
  fi
fi

case "${CRAFT_AGENT_READ_ROOTS:-}" in
  "") CRAFT_AGENT_READ_ROOTS="${RUNNER_TEMP}" ;;
  off) unset CRAFT_AGENT_READ_ROOTS ;;
esac
export CRAFT_AGENT_READ_ROOTS

mode="mission"
journal_dir=""
prompt_file="${RUNNER_TEMP}/craft-agent-prompt.txt"
stream="${RUNNER_TEMP}/craft-agent-stream.jsonl"
read -ra extra_args <<< "${CRAFT_AGENT_ARGS:-}"

# Workflow mode swaps the mission run for the judged workflow plan; its
# stdout carries only the framing events, so the renderer follows the
# run's journal for per-step detail. Mission mode stays the default.
if [ -n "${CRAFT_AGENT_WORKFLOW:-}" ]; then
  mode="workflow"
  # --max-tokens is a per-step cap whose default already equals the
  # plan's run-level total, so the flag is omitted by design.
  agent_cmd=(craft-agent workflow
    --workflow "$CRAFT_AGENT_WORKFLOW"
    --output-format stream-json)
  journal_dir="${GITHUB_WORKSPACE}/.craft-agent/workflows"
else
  printf '%s' "${CRAFT_AGENT_PROMPT:-}" > "$prompt_file"
  agent_cmd=(craft-agent run
    --max-turns "$CRAFT_AGENT_MAX_TURNS"
    --max-tokens "$CRAFT_AGENT_MAX_TOKENS"
    --output-format stream-json
    --prompt "$prompt_file"
    "${extra_args[@]}")
fi
export CRAFT_AGENT_JOURNAL_DIR="$journal_dir"

set +e
"${agent_cmd[@]}" > "$stream" &
agent_pid=$!
# The renderer follows the transcript as the binary writes it and prints
# the run turn by turn into the job log; it exits on its own at the end.
python3 "${GITHUB_WORKSPACE}/scripts/stream-render.py" "$stream" &
renderer_pid=$!
wait "$agent_pid"
rc=$?
# The renderer ends on its own when the terminal event lands; a grace
# window keeps a fast run from being torn mid-flush by the kill below.
for _ in $(seq 1 100); do
  kill -0 "$renderer_pid" 2>/dev/null || break
  sleep 0.1
done
kill -TERM "$renderer_pid" 2>/dev/null || true
wait "$renderer_pid" 2>/dev/null || true
set -e

report=""
failed_step=""
skipped_steps=""
final_message=""
if [ "$mode" = "workflow" ]; then
  # The terminal line is workflow_finished with the whole report; there
  # is no detail field to read a final message from. A missing report
  # means the run never settled — a CLI or plan error, not a failed gate.
  report="$(jq -c 'select(.type == "workflow_finished") | .report' "$stream" 2>/dev/null | tail -n 1 || true)"
  failed_step="$(printf '%s' "$report" | jq -r '.failed_step // ""' 2>/dev/null || true)"
  skipped_steps="$(printf '%s' "$report" | jq -r '[
    .steps[]?
    | select(.status.kind == "skipped")
    | "\(.id)<-\(.status.reason.dep // .status.reason.kind // "?")"
  ] | join(";")' 2>/dev/null || true)"
  final_message="$(printf '%s' "$report" | jq -r '
    "workflow \(.name // "?") \(.conclusion.kind // "?") exit \(.exit_code // 0) failed_step \(.failed_step // "-") skipped \(.steps | map(select(.status.kind == "skipped")) | length)"
  ' 2>/dev/null || true)"
else
  final_message="$(tail -n 1 "$stream" | jq -r 'select(.type == "run_finished") | .detail // ""' 2>/dev/null || true)"
fi

# Workflow exit codes carry a failed step (1) distinctly from an error;
# the mission taxonomy keeps 1 as an error.
case "$mode:$rc" in
  mission:0 | workflow:0) conclusion="success" ;;
  workflow:1) conclusion="failed" ;;
  mission:2 | workflow:2) conclusion="max-turns" ;;
  mission:3 | workflow:3) conclusion="budget" ;;
  *) conclusion="error" ;;
esac
if [ "$mode" = "workflow" ] && [ -z "$report" ]; then
  conclusion="error"
fi
: "${final_message:=workflow produced no report}"
: "${final_message:=}"
{
  echo "conclusion=${conclusion}"
  echo "exit-code=${rc}"
  echo "failed-step=${failed_step}"
  echo "skipped-steps=${skipped_steps}"
  echo "final-message<<CRAFT_AGENT_EOF"
  printf '%s\n' "$final_message"
  echo "CRAFT_AGENT_EOF"
} >> "$GITHUB_OUTPUT"
if [ "$rc" -ne 0 ]; then
  echo "--- craft-agent exit code ${rc}; last stream events: ---"
  tail -n 5 "$stream" || true
  echo "---"
fi
exit "$rc"
