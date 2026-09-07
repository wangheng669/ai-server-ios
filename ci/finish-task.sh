#!/usr/bin/env bash
set -euo pipefail

# --release is the creator's assertion that functional checks are complete and
# no user response is pending. Automated delivery alone never releases a task.
source_branch=""
released=false
while (($#)); do
  case "$1" in
    --source) source_branch=${2:?source branch required}; shift 2 ;;
    --release) released=true; shift ;;
    *) echo 'Usage: ci/finish-task.sh --source codex/task --release' >&2; exit 2 ;;
  esac
done
[[ "$source_branch" == codex/* && "$released" == true ]] || {
  echo 'A task branch and explicit creator release are required.' >&2; exit 2;
}
git check-ref-format --branch "$source_branch" >/dev/null
[[ "$(git branch --show-current)" == main ]] || {
  echo 'Run task cleanup from the primary main checkout.' >&2; exit 1;
}
git fetch --no-tags origin main:refs/remotes/origin/main
source_sha=$(git rev-parse "refs/heads/$source_branch")
git merge-base --is-ancestor "$source_sha" origin/main || {
  echo 'Task is not merged into origin/main.' >&2; exit 1;
}
operations_url=${IOS_DELIVERY_OPERATIONS_URL:-https://api.wanghengai.xin/api/admin/v1/system/ios-delivery-operations}
operations=$(curl --fail --silent --show-error --max-time 15 "$operations_url")
jq -e --arg sha "$source_sha" --arg branch "$source_branch" '
  .data.deployment | .commit == $sha and .sourceBranch == $branch and
  .phase == "succeeded" and .acceptance == "accepted"
' <<<"$operations" >/dev/null || {
  echo 'No matching successful delivery record. Preserve the task; do not infer acceptance from another delivery.' >&2
  exit 1
}
worktree_path=""
candidate=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *) candidate=${line#worktree } ;;
    "branch refs/heads/$source_branch") worktree_path=$candidate ;;
  esac
done < <(git worktree list --porcelain)
if [[ -n "$worktree_path" ]]; then
  [[ -z "$(git -C "$worktree_path" status --porcelain --untracked-files=all)" ]] || {
    echo 'Task has uncommitted files; preserving it.' >&2; exit 1;
  }
  [[ "$(git -C "$worktree_path" rev-parse HEAD)" == "$source_sha" ]] || exit 1
fi
remote_sha=$(git ls-remote --heads origin "refs/heads/$source_branch" | cut -f1)
[[ -z "$remote_sha" || "$remote_sha" == "$source_sha" ]] || {
  echo 'Remote task branch has changed; preserving it.' >&2; exit 1;
}
# Normal deletion only; never force-push or reset another task's history.
if [[ -n "$remote_sha" ]]; then
  git push origin --delete "$source_branch"
fi
if [[ -n "$worktree_path" ]]; then
  git worktree remove "$worktree_path"
fi
git branch -d "$source_branch"
echo "Released and cleaned $source_branch after automated delivery and creator verification."
