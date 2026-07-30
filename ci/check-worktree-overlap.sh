#!/bin/bash

set -euo pipefail

current_root=$(git rev-parse --show-toplevel)
git_common_dir=$(git rev-parse --git-common-dir)
origin_main=origin/main

if ! git show-ref --verify --quiet "refs/remotes/$origin_main"; then
  echo "Missing $origin_main; safely sync or fetch main before checking overlap." >&2
  exit 2
fi

temp_root=$(mktemp -d "${TMPDIR:-/tmp}/ai-server-ios-overlap.XXXXXX")
current_files="$temp_root/current"
other_files="$temp_root/other"
overlap_files="$temp_root/overlap"

cleanup() {
  rm -f "$current_files" "$other_files" "$overlap_files"
  rmdir "$temp_root" 2>/dev/null || true
}
trap cleanup EXIT

collect_changed_files() {
  local worktree=$1
  git -C "$worktree" diff --name-only
  git -C "$worktree" diff --cached --name-only
  git -C "$worktree" ls-files --others --exclude-standard

  if ! git -C "$worktree" merge-base --is-ancestor HEAD "$origin_main"; then
    local merge_base
    merge_base=$(git -C "$worktree" merge-base HEAD "$origin_main")
    git -C "$worktree" diff --name-only "$merge_base"..HEAD
  fi
}

if [[ $# -gt 0 ]]; then
  for target in "$@"; do
    target=${target#"$current_root"/}
    if [[ -d "$current_root/$target" ]]; then
      git -C "$current_root" ls-files -- "$target"
    else
      echo "$target"
    fi
  done | sed '/^$/d' | sort -u > "$current_files"
else
  collect_changed_files "$current_root" | sed '/^$/d' | sort -u > "$current_files"
fi

if [[ ! -s "$current_files" ]]; then
  echo "No current or planned files to check."
  exit 0
fi

conflicts_found=false

while IFS= read -r worktree; do
  [[ "$worktree" == "$current_root" || ! -d "$worktree" ]] && continue

  : > "$other_files"
  collect_changed_files "$worktree" | sed '/^$/d' | sort -u > "$other_files"
  [[ -s "$other_files" ]] || continue

  comm -12 "$current_files" "$other_files" > "$overlap_files"
  [[ -s "$overlap_files" ]] || continue

  conflicts_found=true
  branch=$(git -C "$worktree" branch --show-current)
  echo "Overlap with ${branch:-detached HEAD} at $worktree:" >&2
  sed 's/^/  - /' "$overlap_files" >&2
done < <(git --git-dir="$git_common_dir" worktree list --porcelain | sed -n 's/^worktree //p')

if [[ "$conflicts_found" == true ]]; then
  echo "Coordinate or serialize these tasks before editing or submitting." >&2
  exit 1
fi

echo "No overlapping files found in active worktrees."
