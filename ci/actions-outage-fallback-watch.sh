#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [[ "$(git branch --show-current)" != main ]] || [[ -n "$(git status --short)" ]]; then
  echo "Outage fallback watcher requires a clean main checkout." >&2
  exit 0
fi

actions_status=$(curl --fail --silent --show-error \
  https://www.githubstatus.com/api/v2/components.json \
  | jq -r '.components[] | select(.name == "Actions") | .status')
if [[ "$actions_status" != partial_outage && "$actions_status" != major_outage ]]; then
  exit 0
fi

minimum_queue_seconds=${IOS_ACTIONS_OUTAGE_QUEUE_SECONDS:-300}
now_epoch=$(date +%s)
queued_runs=$(gh run list \
  --workflow 'AI merge task branch into main' \
  --status queued \
  --limit 20 \
  --json databaseId,createdAt,headBranch,headSha \
  2>/dev/null || true)

eligible_runs=$(jq -c --argjson now "$now_epoch" --argjson minimum "$minimum_queue_seconds" '
  map(select(.headBranch | startswith("codex/")))
  | map(. + {createdEpoch: (.createdAt | fromdateiso8601)})
  | map(select(($now - .createdEpoch) >= $minimum))
  | group_by(.headBranch)
  | map(max_by(.createdEpoch))
  | sort_by(.createdEpoch)
  | .[]
' <<<"${queued_runs:-[]}")

git fetch --no-tags origin main:refs/remotes/origin/main
candidate=""
while IFS= read -r run; do
  [[ -n "$run" ]] || continue
  branch=$(jq -r .headBranch <<<"$run")
  run_sha=$(jq -r .headSha <<<"$run")
  if ! git fetch --no-tags origin "$branch:refs/remotes/origin/$branch"; then
    continue
  fi
  branch_sha=$(git rev-parse "origin/$branch")
  if [[ "$branch_sha" != "$run_sha" ]] || git merge-base --is-ancestor "$run_sha" origin/main; then
    continue
  fi
  candidate=$run
  break
done <<<"$eligible_runs"
[[ -n "$candidate" ]] || exit 0

run_id=$(jq -r .databaseId <<<"$candidate")
source_branch=$(jq -r .headBranch <<<"$candidate")
echo "Taking over queued outage run $run_id for $source_branch."
exec ./ci/local-central-merge.sh \
  --source "$source_branch" \
  --run "$run_id" \
  --confirm-infrastructure-failure
