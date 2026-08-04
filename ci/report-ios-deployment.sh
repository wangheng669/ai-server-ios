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

payload=$(printf '{"phase":"%s","progress":%s,"stage":"%s","commit":"%s","runId":"%s"}' \
  "$phase" "$progress" "$stage" "${GITHUB_SHA:-}" "${GITHUB_RUN_ID:-}")

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
