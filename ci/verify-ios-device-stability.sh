#!/usr/bin/env bash
set -euo pipefail

: "${DEVICE_UDID:?DEVICE_UDID is required}"

attempts=${IOS_DEVICE_STABILITY_ATTEMPTS:-3}
interval_seconds=${IOS_DEVICE_STABILITY_INTERVAL_SECONDS:-5}
if ! [[ "$attempts" =~ ^[1-9][0-9]*$ && "$interval_seconds" =~ ^[0-9]+$ ]]; then
  echo "Device stability attempts and interval must be non-negative integers." >&2
  exit 2
fi

for ((attempt = 1; attempt <= attempts; attempt++)); do
  details=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-device-stability.XXXXXX")
  if ! xcrun devicectl device info details --device "$DEVICE_UDID" --json-output "$details" >/dev/null 2>&1; then
    echo "检测 $attempt/$attempts 失败：CoreDevice 未发现目标 iPhone。请保持 USB 连接并解锁手机。" >&2
    exit 1
  fi

  device_name=$(jq -r '.result.deviceProperties.name // .result.hardwareProperties.marketingName // empty' "$details")
  if ! ioreg -p IOUSB -l -w 0 | grep -Fq "$DEVICE_UDID"; then
    echo "检测 $attempt/$attempts 失败：${device_name:-目标 iPhone} 未通过 USB 有线连接。" >&2
    exit 1
  fi

  if ! xcrun devicectl device process list --device "$DEVICE_UDID" >/dev/null 2>&1; then
    echo "检测 $attempt/$attempts 失败：${device_name:-目标 iPhone} 当前锁定，或可信开发连接尚未就绪。" >&2
    exit 1
  fi

  if ! xcodebuild -project AIServerClient.xcodeproj -scheme AIServerClient -showdestinations 2>/dev/null \
    | grep -Fq "id:$DEVICE_UDID"; then
    echo "检测 $attempt/$attempts 失败：Xcode 尚未识别 ${device_name:-目标 iPhone}。" >&2
    exit 1
  fi

  echo "真机稳定性检测 $attempt/$attempts 通过：${device_name:-$DEVICE_UDID} 已有线连接、解锁且可供 Xcode 使用。"
  if [[ "$attempt" -lt "$attempts" ]]; then
    sleep "$interval_seconds"
  fi
done

echo "真机稳定性门禁通过：连续 $attempts 次检测正常。"
