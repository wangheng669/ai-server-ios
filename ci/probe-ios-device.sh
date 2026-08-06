#!/usr/bin/env bash
set -euo pipefail

: "${DEVICE_UDID:?DEVICE_UDID is required}"
: "${DEPLOYMENT_STATUS_API_KEY:?DEPLOYMENT_STATUS_API_KEY is required}"

started_epoch=$(date +%s)
base_url=${DEPLOYMENT_STATUS_BASE_URL:-https://api.wanghengai.xin}
report_url="$base_url/api/ios/v1/ios/device-probe-report"

report() {
  local state=$1 stage=$2 message=$3 device_name=${4:-}
  local duration=$(($(date +%s) - started_epoch))
  jq -cn \
    --arg state "$state" --arg stage "$stage" --arg runner "${RUNNER_NAME:-central-mac}" \
    --arg deviceId "$DEVICE_UDID" --arg deviceName "$device_name" --arg message "$message" \
    --argjson durationSeconds "$duration" \
    '{state:$state,stage:$stage,runner:$runner,deviceId:$deviceId,deviceName:$deviceName,message:$message,durationSeconds:$durationSeconds}' \
    | curl --fail-with-body --silent --show-error --max-time 15 \
      -X POST -H 'Content-Type: application/json' -H "X-API-Key: $DEPLOYMENT_STATUS_API_KEY" \
      --data-binary @- "$report_url"
}

report running checking-stability "中央 Mac 正在连续检查设备连接、解锁状态与 Xcode 可用性" >/dev/null
details=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-device-probe.XXXXXX")
if ! xcrun devicectl device info details --device "$DEVICE_UDID" --json-output "$details" >/dev/null 2>&1; then
  report unavailable device-not-found "中央 Mac 未发现目标 iPhone；请确认手机已解锁，并通过 USB 或已配对的无线调试连接" >/dev/null
  exit 1
fi

device_name=$(jq -r '.result.deviceProperties.name // .result.hardwareProperties.marketingName // empty' "$details")
probe_log=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-device-probe-log.XXXXXX")
if ! ./ci/verify-ios-device-stability.sh > >(tee "$probe_log") 2>&1; then
  message=$(tail -1 "$probe_log")
  report unavailable stability-failed "${message:-真机连接不稳定，已阻止后续交付}" "$device_name" >/dev/null
  exit 1
fi

report ready device-ready "连续检测通过：真机连接稳定且已解锁，CoreDevice 与 Xcode 均可部署" "$device_name" >/dev/null
