#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="${1:-$(git rev-parse --show-toplevel)}"
cd "$repo_dir"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

git rev-parse --show-toplevel >/dev/null

lock_dir="${TMPDIR:-/tmp}/ai-server-ios-main-sync-$(id -u).lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  log "Another automatic sync is already running."
  exit 0
fi
trap 'rmdir "$lock_dir"' EXIT

if [[ -n "$(git status --porcelain)" ]]; then
  log "Skipped: the primary working tree has uncommitted changes."
  exit 0
fi

"$script_dir/git-fetch-origin.sh" --prune --no-tags origin

if ! git show-ref --verify --quiet refs/remotes/origin/main; then
  log "Skipped: origin/main is unavailable."
  exit 0
fi

current_branch="$(git branch --show-current)"
case "$current_branch" in
  main)
    ;;
  codex/*)
    log "Skipped: task workspaces are managed by their creator."
    exit 0
    ;;
  "")
    log "Skipped: the primary working tree has a detached HEAD."
    exit 0
    ;;
  *)
    log "Skipped: the primary working tree is on protected branch $current_branch."
    exit 0
    ;;
esac

if ! git merge-base --is-ancestor main origin/main; then
  log "Skipped: local main has commits or history that are not in origin/main."
  exit 0
fi

git merge --ff-only origin/main

# Task cleanup is explicit and belongs to ci/finish-task.sh.

log "Primary working tree is clean on origin/main at $(git rev-parse --short HEAD)."
