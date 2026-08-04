#!/usr/bin/env bash
set -euo pipefail

phase=${1:?phase is required}
progress=${2:?progress is required}
stage=${3:-}
base_url=${DEPLOYMENT_STATUS_BASE_URL:-https://api.wanghengai.xin}
api_key=${DEPLOYMENT_STATUS_API_KEY:-}

if [[ -z "$api_key" ]]; then
  echo "DEPLOYMENT_STATUS_API_KEY is not configured" >&2
  exit 1
fi

payload=$(printf '{"phase":"%s","progress":%s,"stage":"%s","commit":"%s","runId":"%s"}' \
  "$phase" "$progress" "$stage" "${GITHUB_SHA:-}" "${GITHUB_RUN_ID:-}")

curl --fail --silent --show-error \
  --connect-timeout 5 \
  --max-time 15 \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $api_key" \
  --data "$payload" \
  "$base_url/api/ios/v1/system/ios-deployment" >/dev/null
