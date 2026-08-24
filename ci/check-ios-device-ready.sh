#!/usr/bin/env bash
set -euo pipefail

: "${DEVICE_UDID:?DEVICE_UDID is required}"

project=${IOS_XCODE_PROJECT:-AIServerClient.xcodeproj}
scheme=${IOS_XCODE_SCHEME:-AIServerClient}
result_path=${IOS_DEVICE_READY_JSON:-}
temporary_root=${RUNNER_TEMP:-/tmp}
details=$(mktemp "$temporary_root/ios-device-ready.XXXXXX")
process_log=$(mktemp "$temporary_root/ios-device-processes.XXXXXX")
destinations=$(mktemp "$temporary_root/ios-xcode-destinations.XXXXXX")
cleanup() {
  rm -f "$details" "$process_log" "$destinations"
}
trap cleanup EXIT

if ! xcrun devicectl device info details --device "$DEVICE_UDID" --json-output "$details" >/dev/null 2>&1; then
  echo "CoreDevice 未发现目标 iPhone。请保持 USB 连接并解锁手机。" >&2
  exit 1
fi

device_name=$(jq -r '.result.deviceProperties.name // .result.hardwareProperties.marketingName // empty' "$details")
xcode_device_id=$(jq -r '.result.hardwareProperties.udid // empty' "$details")
xcode_device_id=${xcode_device_id:-$DEVICE_UDID}

if ! xcrun devicectl device info processes --device "$DEVICE_UDID" >"$process_log" 2>&1; then
  echo "${device_name:-目标 iPhone} 已被发现，但 CoreDevice 开发服务连接尚未就绪。" >&2
  exit 1
fi

if ! xcodebuild -project "$project" -scheme "$scheme" -showdestinations >"$destinations" 2>&1; then
  echo "Xcode 无法读取 $scheme 的可用目标。" >&2
  exit 1
fi
if ! grep -Fq "id:$xcode_device_id" "$destinations"; then
  echo "Xcode 尚未识别 ${device_name:-目标 iPhone}；设备可能仍处于 Preparing。" >&2
  exit 1
fi

if [[ -n "$result_path" ]]; then
  jq -cn \
    --arg deviceId "$xcode_device_id" \
    --arg deviceName "$device_name" \
    --arg runnerName "${RUNNER_NAME:-$(scutil --get ComputerName 2>/dev/null || hostname)}" \
    --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{deviceId:$deviceId,deviceName:$deviceName,runnerName:$runnerName,checkedAt:$checkedAt}' \
    >"$result_path"
fi

echo "${device_name:-$DEVICE_UDID} 已通过 CoreDevice、开发服务与 Xcode 部署目标检查。"
