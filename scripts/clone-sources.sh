#!/usr/bin/env bash
# One clone attempt for the adoption scan's source sweep.
# Usage: clone-sources.sh <method> <owner/name> <dest> [sparse paths...]
#   methods: sparse   depth-1 blobless clone, sparse-checkout the given paths
#            full     depth-1 clone of the whole tree at HEAD
#            tarball  codeload tarball of HEAD, extracted (no .git)
# Prints attempt log lines to stderr (safe to surface) and nothing that
# derives from a secret. Auth rides env only: git reads the extraheader from
# GIT_CONFIG_* when git_auth sets them; tarball reads a umask-077 header file
# via `curl -H @file` and deletes it. Exit 0 on a populated dest.
set -uo pipefail

method="${1:?method required}"
repo="${2:?owner/name required}"
dest="${3:?dest required}"
shift 3
paths=("$@")

export GIT_TERMINAL_PROMPT=0
umask 077

git_auth() {
  # Token only ever enters the child process env, never argv or disk.
  if [ -n "${GH_TOKEN:-}" ]; then
    local b64
    b64="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
    export GIT_CONFIG_VALUE_0="Authorization: Basic ${b64}"
  fi
}

url="https://github.com/${repo}.git"
log() { printf '[clone-sources] %s %s: %s\n' "$method" "$repo" "$1" >&2; }
fail() { log "$1"; exit 1; }

# Dest is the sweep's own tree; validate its shape before any filesystem work.
case "$dest" in
  sources/*) ;;
  *) fail "dest must be sources/<name>: $dest" ;;
esac
name="${dest#sources/}"
if [ -z "$name" ] || [ "$name" = "." ] || [ "$name" = ".." ] \
   || [[ "$name" =~ [^A-Za-z0-9._-] ]]; then
  fail "bad dest name: $name"
fi

[ -e "$dest" ] && fail "dest already exists"

mkdir -p "$(dirname "$dest")" || fail "cannot create parent of $dest"

case "$method" in
  sparse | full)
    git_auth
    if [ "$method" = sparse ]; then
      [ "${#paths[@]}" -gt 0 ] || fail "sparse needs watch-paths"
      git clone --quiet --depth 1 --filter=blob:none --sparse "$url" "$dest" \
        || fail "git clone failed"
      # Cone-mode sparse-checkout takes directories only. Root-level files
      # come with any directory pattern; file paths outside the root are
      # fetched on demand below.
      dirs=(); files=()
      for p in "${paths[@]}"; do
        case "${p##*/}" in
          *.*) files+=("$p") ;;
          *) dirs+=("$p") ;;
        esac
      done
      if [ "${#dirs[@]}" -gt 0 ]; then
        git -C "$dest" sparse-checkout set "${dirs[@]}" >/dev/null 2>&1 \
          || fail "sparse-checkout failed for: ${dirs[*]}"
      fi
      for p in "${files[@]}"; do
        if [ ! -e "$dest/$p" ]; then
          mkdir -p "$(dirname "$dest/$p")"
          git -C "$dest" show "HEAD:$p" >"$dest/$p" 2>/dev/null \
            || { rm -f "$dest/$p"; fail "watch-path missing: $p"; }
        fi
      done
      # Cone mode always includes root files, so a bad path still yields a
      # non-empty tree — verify the requested paths themselves.
      for p in "${paths[@]}"; do
        if [ -d "$dest/$p" ]; then
          [ "$(find "$dest/$p" -type f | wc -l)" -gt 0 ] \
            || fail "watch-path empty: $p"
        elif [ ! -e "$dest/$p" ]; then
          fail "watch-path missing: $p"
        fi
      done
    else
      git clone --quiet --depth 1 "$url" "$dest" || fail "git clone failed"
    fi
    [ -n "$(git -C "$dest" rev-parse --short HEAD 2>/dev/null)" ] \
      || fail "clone produced no HEAD"
    ;;
  tarball)
    [ -n "${GH_TOKEN:-}" ] || log "no GH_TOKEN; attempting anonymous tarball"
    hdr="$(dirname "$dest")/.hdr.$$"
    trap 'rm -f "$hdr"' EXIT
    if [ -n "${GH_TOKEN:-}" ]; then
      printf 'Authorization: Basic %s\n' \
        "$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')" \
        >"$hdr"
    fi
    tarball="$(dirname "$dest")/tarball.$$.tar.gz"
    trap 'rm -f "$hdr" "$tarball"' EXIT
    curl_args=(--fail --silent --show-error --location --max-time 900)
    [ -s "$hdr" ] && curl_args+=(-H "@$hdr")
    curl "${curl_args[@]}" \
      "https://codeload.github.com/${repo}/tar.gz/HEAD" -o "$tarball" \
      || fail "tarball fetch failed"
    mkdir -p "$dest" || fail "cannot create $dest"
    tar -xzf "$tarball" -C "$dest" --strip-components=1 \
      || fail "tarball extract failed"
    ;;
  *)
    fail "unknown method: $method"
    ;;
esac

n=$(find "$dest" -type f | wc -l)
[ "$n" -gt 0 ] || fail "dest empty after $method"
log "ok: ${n} files"
exit 0
