#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./ci/select-current-ios-central-mac.sh [--apply]

Checks the current Mac, its GitHub runner state, CoreDevice, and Xcode destination.
With --apply, updates IOS_CENTRAL_RUNNER_LABEL to the current Mac's label.
EOF
}

apply=false
case "${1:-}" in
  "") ;;
  --apply) apply=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

: "${DEVICE_UDID:?DEVICE_UDID is required}"
computer_name=$(scutil --get ComputerName)
case "$computer_name" in
  *"MacBook Air"*) runner_label=home-installer ;;
  *"Mac mini"*) runner_label=office-builder ;;
  *)
    echo "当前电脑名称无法映射到中央 Runner：$computer_name" >&2
    exit 1
    ;;
esac

operations_url=${IOS_DELIVERY_OPERATIONS_URL:-https://api.wanghengai.xin/api/admin/v1/system/ios-delivery-operations}
operations=$(curl --fail --silent --show-error --max-time 15 "$operations_url")
runner_state=$(jq -r --arg label "$runner_label" '
  [.data.runners[] | select(.labels | index($label))] |
  if length == 0 then "missing"
  elif any(.status == "online" and (.busy | not)) then "ready"
  elif any(.status == "online") then "busy"
  else "offline" end
' <<<"$operations")
if [[ "$runner_state" == missing || "$runner_state" == offline ]]; then
  echo "$runner_label Runner 当前状态为 ${runner_state}，不能选作中央 Mac。" >&2
  exit 1
fi
if [[ "$runner_state" == busy ]]; then
  echo "$runner_label Runner 正在执行任务；新交付会在同一 Runner 上排队。"
fi

./ci/check-ios-device-ready.sh

if [[ "$apply" == true ]]; then
  command -v gh >/dev/null 2>&1 || { echo "gh 未安装，无法更新仓库变量。" >&2; exit 1; }
  gh auth status >/dev/null
  gh variable set IOS_CENTRAL_RUNNER_LABEL --body "$runner_label"
  echo "已将 IOS_CENTRAL_RUNNER_LABEL 更新为 ${runner_label}。"
else
  echo "推荐中央 Mac：${computer_name}（${runner_label}）。使用 --apply 写入仓库变量。"
fi
