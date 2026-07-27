#!/bin/bash

set -euo pipefail

repo_dir="${1:-$(git rev-parse --show-toplevel)}"
cd "$repo_dir"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Skipping daily main sync: working tree has uncommitted changes."
  exit 0
fi

current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "main" ]]; then
  echo "Skipping daily main sync: current branch is $current_branch, not main."
  exit 0
fi

./ci/safe-sync.sh main

git for-each-ref --format='%(refname:short)' --merged origin/main refs/heads/codex/ |
while read -r branch; do
  [[ -n "$branch" ]] || continue
  git branch -d "$branch"
done
