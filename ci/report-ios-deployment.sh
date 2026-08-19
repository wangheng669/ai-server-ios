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
device_warm_seconds=$(json_seconds "${IOS_DEVICE_WARM_SECONDS:-}")
dependency_seconds=$(json_seconds "${IOS_DEPENDENCY_SECONDS:-}")
device_build_warm_seconds=$(json_seconds "${IOS_DEVICE_BUILD_WARM_SECONDS:-}")
simulator_warm_seconds=$(json_seconds "${IOS_SIMULATOR_WARM_SECONDS:-}")
merge_seconds=$(json_seconds "${IOS_MERGE_SECONDS:-}")
build_seconds=$(json_seconds "${IOS_BUILD_SECONDS:-}")
install_seconds=$(json_seconds "${IOS_INSTALL_SECONDS:-}")
device_wait_seconds=$(json_seconds "${IOS_DEVICE_WAIT_DURATION_SECONDS:-}")
direct_install_seconds=$(json_seconds "${IOS_DIRECT_INSTALL_SECONDS:-}")
xcode_recovery_seconds=$(json_seconds "${IOS_XCODE_RECOVERY_SECONDS:-}")
final_install_seconds=$(json_seconds "${IOS_FINAL_INSTALL_SECONDS:-}")
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
deployment_commit=${IOS_DEPLOYMENT_COMMIT:-${GITHUB_SHA:-}}
deployment_source_branch=${IOS_DEPLOYMENT_SOURCE_BRANCH:-${GITHUB_REF_NAME:-}}
deployment_run_id=${IOS_DEPLOYMENT_RUN_ID:-${GITHUB_RUN_ID:-}}
if [[ -z "$commit_message" && -n "$deployment_commit" ]] && git cat-file -e "${deployment_commit}^{commit}" 2>/dev/null; then
  commit_message=$(git log -1 --format=%s "$deployment_commit")
fi

payload=$(jq -cn \
  --arg phase "$phase" \
  --argjson progress "$progress" \
  --arg stage "$stage" \
  --arg commit "$deployment_commit" \
  --arg commitMessage "$commit_message" \
  --arg sourceBranch "$deployment_source_branch" \
  --arg runId "$deployment_run_id" \
  --argjson preflight "$preflight_seconds" \
  --argjson prepare "$prepare_seconds" \
  --argjson deviceWarm "$device_warm_seconds" \
  --argjson dependency "$dependency_seconds" \
  --argjson deviceBuildWarm "$device_build_warm_seconds" \
  --argjson simulatorWarm "$simulator_warm_seconds" \
  --argjson merge "$merge_seconds" \
  --argjson build "$build_seconds" \
  --argjson deviceWait "$device_wait_seconds" \
  --argjson directInstall "$direct_install_seconds" \
  --argjson xcodeRecovery "$xcode_recovery_seconds" \
  --argjson finalInstall "$final_install_seconds" \
  --argjson install "$device_delivery_seconds" \
  --argjson total "$total_seconds" \
  '{phase:$phase, progress:$progress, stage:$stage, commit:$commit, commitMessage:$commitMessage,
    sourceBranch:$sourceBranch, runId:$runId,
    timings:{preflight:$preflight, prepare:$prepare, deviceWarm:$deviceWarm,
      dependency:$dependency, deviceBuildWarm:$deviceBuildWarm, simulatorWarm:$simulatorWarm, merge:$merge, build:$build,
      deviceWait:$deviceWait, directInstall:$directInstall, xcodeRecovery:$xcodeRecovery,
      finalInstall:$finalInstall, install:$install, queue:null, total:$total}}')

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
