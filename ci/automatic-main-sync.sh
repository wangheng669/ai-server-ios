#!/bin/bash

set -euo pipefail

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

git fetch --prune --no-tags origin

if ! git show-ref --verify --quiet refs/remotes/origin/main; then
  log "Skipped: origin/main is unavailable."
  exit 0
fi

current_branch="$(git branch --show-current)"
case "$current_branch" in
  main)
    ;;
  codex/*)
    if ! git merge-base --is-ancestor HEAD origin/main; then
      log "Skipped: $current_branch has not been merged into origin/main."
      exit 0
    fi
    git switch main
    log "Returned the primary working tree to main after $current_branch was merged."
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

primary_worktree="$(git rev-parse --show-toplevel)"
codex_worktree_root="$HOME/.codex/worktrees/"

while IFS= read -r worktree_path; do
  [[ -n "$worktree_path" && "$worktree_path" != "$primary_worktree" ]] || continue
  case "$worktree_path/" in
    "$codex_worktree_root"*) ;;
    *) continue ;;
  esac

  worktree_branch="$(git -C "$worktree_path" branch --show-current 2>/dev/null || true)"
  [[ "$worktree_branch" == codex/* ]] || continue
  git merge-base --is-ancestor "$worktree_branch" origin/main 2>/dev/null || continue
  [[ -z "$(git -C "$worktree_path" status --porcelain 2>/dev/null)" ]] || continue

  git worktree remove "$worktree_path"
  log "Removed merged task worktree $worktree_path."
done < <(git worktree list --porcelain | sed -n 's/^worktree //p')

git worktree prune

while IFS= read -r branch; do
  [[ -n "$branch" ]] || continue
  if git branch -d "$branch" >/dev/null; then
    log "Deleted merged local branch $branch."
  fi
done < <(
  git for-each-ref \
    --format='%(refname:short)' \
    --merged origin/main \
    refs/heads/codex/
)

log "Primary working tree is clean on origin/main at $(git rev-parse --short HEAD)."
