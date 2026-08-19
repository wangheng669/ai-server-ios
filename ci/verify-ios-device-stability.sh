#!/usr/bin/env bash
set -euo pipefail

: "${DEVICE_UDID:?DEVICE_UDID is required}"

required_successes=${IOS_DEVICE_STABILITY_ATTEMPTS:-3}
max_attempts=${IOS_DEVICE_STABILITY_MAX_ATTEMPTS:-18}
interval_seconds=${IOS_DEVICE_STABILITY_INTERVAL_SECONDS:-5}
if ! [[ "$required_successes" =~ ^[1-9][0-9]*$ \
  && "$max_attempts" =~ ^[1-9][0-9]*$ \
  && "$interval_seconds" =~ ^[0-9]+$ ]]; then
  echo "Device stability attempts must be positive integers and the interval must be a non-negative integer." >&2
  exit 2
fi
if ((max_attempts < required_successes)); then
  echo "Device stability max attempts must be at least the required consecutive successes." >&2
  exit 2
fi

consecutive_successes=0
last_failure='目标 iPhone 尚未就绪。'
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  details=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-device-stability.XXXXXX")
  if ! xcrun devicectl device info details --device "$DEVICE_UDID" --json-output "$details" >/dev/null 2>&1; then
    last_failure='CoreDevice 未发现目标 iPhone。请保持 USB 连接并解锁手机。'
  else
    device_name=$(jq -r '.result.deviceProperties.name // .result.hardwareProperties.marketingName // empty' "$details")
    xcode_device_id=$(jq -r '.result.hardwareProperties.udid // empty' "$details")
    xcode_device_id=${xcode_device_id:-$DEVICE_UDID}
    process_log=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-device-processes.XXXXXX")
    if ! xcrun devicectl device info processes --device "$DEVICE_UDID" >"$process_log" 2>&1; then
      last_failure="${device_name:-目标 iPhone} 已被发现，但 CoreDevice 开发服务连接尚未就绪；这不一定表示手机锁定。"
    elif ! xcodebuild -project AIServerClient.xcodeproj -scheme AIServerClient -showdestinations 2>/dev/null \
      | grep -Fq "id:$xcode_device_id"; then
      last_failure="Xcode 尚未识别 ${device_name:-目标 iPhone}。"
    else
      consecutive_successes=$((consecutive_successes + 1))
      echo "真机稳定性检测连续成功 ${consecutive_successes}/${required_successes}（总探测 ${attempt}/${max_attempts}）：${device_name:-$DEVICE_UDID} 连接稳定、已解锁且可供 Xcode 使用。"
      if ((consecutive_successes >= required_successes)); then
        echo "真机稳定性门禁通过：连续 ${required_successes} 次检测正常。"
        exit 0
      fi
      if ((attempt < max_attempts)); then
        sleep "$interval_seconds"
      fi
      continue
    fi
  fi

  consecutive_successes=0
  echo "真机稳定性检测 ${attempt}/${max_attempts} 暂未通过：${last_failure} 将继续重试。" >&2
  if ((attempt < max_attempts)); then
    sleep "$interval_seconds"
  fi
done

echo "真机稳定性门禁失败：${max_attempts} 次探测内未能连续成功 ${required_successes} 次。最后原因：${last_failure}" >&2
exit 1
