#!/bin/bash

set -euo pipefail

target_branch="${1:-main}"

git rev-parse --show-toplevel >/dev/null

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Refusing to sync because the working tree has uncommitted changes." >&2
  echo "Commit or stash the current task before syncing." >&2
  exit 1
fi

git fetch --prune origin

if ! git show-ref --verify --quiet "refs/remotes/origin/$target_branch"; then
  echo "Remote branch origin/$target_branch does not exist." >&2
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/$target_branch"; then
  git switch "$target_branch"
else
  git switch --track -c "$target_branch" "origin/$target_branch"
fi

git merge --ff-only "origin/$target_branch"

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$target_branch")" ]]; then
  echo "Local $target_branch contains commits that have not been pushed to origin." >&2
  echo "Push or reconcile those commits before starting another task." >&2
  exit 1
fi

echo "Synced to origin/$target_branch at $(git rev-parse --short HEAD)."
