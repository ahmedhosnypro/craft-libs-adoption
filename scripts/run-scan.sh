#!/usr/bin/env bash
# Runs the adoption-scan mission with the live stream renderer attached.
# Self-contained on purpose: the composite action funnels the binary's
# stdout into the transcript file, so nothing reaches the job log while a
# run is alive; this wrapper installs the same release binaries, runs the
# mission, and renders the stream into the log turn by turn.
set -euo pipefail

VERSION="${CRAFT_AGENT_VERSION:-v0.0.4}"
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

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git config --global user.name "craft-agent"
git config --global user.email "agent@craft-agent.invalid"

prompt_file="${RUNNER_TEMP}/craft-agent-prompt.txt"
printf '%s' "$CRAFT_AGENT_PROMPT" > "$prompt_file"

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

stream="${RUNNER_TEMP}/craft-agent-stream.jsonl"
read -ra extra_args <<< "${CRAFT_AGENT_ARGS:-}"

set +e
craft-agent run \
  --max-turns "$CRAFT_AGENT_MAX_TURNS" \
  --max-tokens "$CRAFT_AGENT_MAX_TOKENS" \
  --output-format stream-json \
  --prompt "$prompt_file" \
  "${extra_args[@]}" > "$stream" &
agent_pid=$!
# The renderer follows the transcript as the binary writes it and prints
# the run turn by turn into the job log; it exits on its own at the end.
python3 "${GITHUB_WORKSPACE}/scripts/stream-render.py" "$stream" &
renderer_pid=$!
wait "$agent_pid"
rc=$?
kill -TERM "$renderer_pid" 2>/dev/null || true
wait "$renderer_pid" 2>/dev/null || true
set -e

case "$rc" in
  0) conclusion="success" ;;
  2) conclusion="max-turns" ;;
  3) conclusion="budget" ;;
  *) conclusion="error" ;;
esac
final_message="$(tail -n 1 "$stream" | jq -r 'select(.type == "run_finished") | .detail // ""' 2>/dev/null || true)"
: "${final_message:=}"
{
  echo "conclusion=${conclusion}"
  echo "exit-code=${rc}"
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
