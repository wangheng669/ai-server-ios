#!/usr/bin/env bash
set -euo pipefail

phase=${1:?phase is required}
progress=${2:?progress is required}
stage=${3:-}
base_url=${DEPLOYMENT_STATUS_BASE_URL:-https://api.wanghengai.xin}
preferred_path=${DEPLOYMENT_STATUS_API_PATH:-/api/ios/v1/system/ios-deployment}
api_key=${DEPLOYMENT_STATUS_API_KEY:-}

if [[ -z "$api_key" ]]; then
  echo "DEPLOYMENT_STATUS_API_KEY is not configured" >&2
  exit 1
fi

json_seconds() {
  local value=${1:-}
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf 'null'
  fi
}

preflight_seconds=$(json_seconds "${IOS_PREFLIGHT_SECONDS:-}")
prepare_seconds=$(json_seconds "${IOS_PREPARE_SECONDS:-}")
merge_seconds=$(json_seconds "${IOS_MERGE_SECONDS:-}")
build_seconds=$(json_seconds "${IOS_BUILD_SECONDS:-}")
install_seconds=$(json_seconds "${IOS_INSTALL_SECONDS:-}")
workflow_started=$(json_seconds "${IOS_WORKFLOW_STARTED_EPOCH:-}")
device_delivery_seconds=null
if [[ "$build_seconds" != null && "$install_seconds" != null ]]; then
  device_delivery_seconds=$((build_seconds + install_seconds))
fi
total_seconds=null
if [[ "$workflow_started" != null ]]; then
  total_seconds=$(($(date +%s) - workflow_started))
fi

commit_message=${IOS_COMMIT_MESSAGE:-}
if [[ -z "$commit_message" && -n "${GITHUB_SHA:-}" ]] && git cat-file -e "${GITHUB_SHA}^{commit}" 2>/dev/null; then
  commit_message=$(git log -1 --format=%s "$GITHUB_SHA")
fi

payload=$(jq -cn \
  --arg phase "$phase" \
  --argjson progress "$progress" \
  --arg stage "$stage" \
  --arg commit "${GITHUB_SHA:-}" \
  --arg commitMessage "$commit_message" \
  --arg sourceBranch "${GITHUB_REF_NAME:-}" \
  --arg runId "${GITHUB_RUN_ID:-}" \
  --argjson preflight "$preflight_seconds" \
  --argjson prepare "$prepare_seconds" \
  --argjson merge "$merge_seconds" \
  --argjson install "$device_delivery_seconds" \
  --argjson total "$total_seconds" \
  '{phase:$phase, progress:$progress, stage:$stage, commit:$commit, commitMessage:$commitMessage,
    sourceBranch:$sourceBranch, runId:$runId,
    timings:{preflight:$preflight, prepare:$prepare, merge:$merge, install:$install, queue:null, total:$total}}')

for path in "$preferred_path" /api/v1/system/ios-deployment; do
  status=$(curl --silent --show-error \
    --connect-timeout 5 \
    --max-time 15 \
    -o /dev/null \
    -w '%{http_code}' \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $api_key" \
    --data "$payload" \
    "$base_url$path")
  if [[ "$status" =~ ^2 ]]; then
    exit 0
  fi
  if [[ "$status" != "404" ]]; then
    echo "Deployment status report failed with HTTP $status" >&2
    exit 1
  fi
done

echo "Deployment status endpoint was not found" >&2
exit 1
