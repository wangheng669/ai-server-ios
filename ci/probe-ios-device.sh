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

report running checking-coredevice "中央 Mac 正在检查 CoreDevice 连接" >/dev/null
details=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-device-probe.XXXXXX")
if ! xcrun devicectl device info details --device "$DEVICE_UDID" --json-output "$details" >/dev/null 2>&1; then
  report unavailable device-not-found "中央 Mac 未发现目标 iPhone；请确认手机已解锁并连接 USB 或无线调试" >/dev/null
  exit 1
fi

device_name=$(jq -r '.. | .name? // empty' "$details" | head -1)
report running checking-xcode "CoreDevice 已发现手机，正在确认 Xcode 可用性" "$device_name" >/dev/null
if ! xcodebuild -project AIServerClient.xcodeproj -scheme AIServerClient -showdestinations 2>/dev/null \
  | grep -Fq "id:$DEVICE_UDID"; then
  report unavailable xcode-unavailable "手机已连接，但 Xcode 暂时不能用于构建或安装" "$device_name" >/dev/null
  exit 1
fi

report ready device-ready "真机在线，CoreDevice 与 Xcode 均可用于部署" "$device_name" >/dev/null
