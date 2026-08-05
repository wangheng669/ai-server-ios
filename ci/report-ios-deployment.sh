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

payload=$(printf '{"phase":"%s","progress":%s,"stage":"%s","commit":"%s","runId":"%s","timings":{"preflight":%s,"merge":%s,"install":%s,"queue":null,"total":%s}}' \
  "$phase" "$progress" "$stage" "${GITHUB_SHA:-}" "${GITHUB_RUN_ID:-}" \
  "$preflight_seconds" "$merge_seconds" "$device_delivery_seconds" "$total_seconds")

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
