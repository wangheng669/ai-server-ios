#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

workflow_started_epoch=$(date +%s)
git fetch --no-tags --deepen=50 origin \
  "${GITHUB_SHA:-HEAD}" \
  main:refs/remotes/origin/main
preflight_started_epoch=$workflow_started_epoch
preflight_finished_epoch_file=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-preflight-finished.XXXXXX")

(
  set +e
  IOS_PREFLIGHT_SKIP_FETCH=true ./ci/linux-preflight.sh origin/main
  status=$?
  date +%s > "$preflight_finished_epoch_file"
  exit "$status"
) &
preflight_pid=$!

device_warm_started_epoch=$(date +%s)
device_warm_finished_epoch_file=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-device-warm-finished.XXXXXX")
if [[ -n "${DEVICE_UDID:-}" && -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
  ./ci/report-ios-deployment.sh running 0.01 warming-device-connection || true
fi
(
  if [[ -n "${DEVICE_UDID:-}" ]]; then
    xcrun devicectl device info details --device "$DEVICE_UDID" >/dev/null 2>&1 || true
  fi
  date +%s > "$device_warm_finished_epoch_file"
) &
device_warm_pid=$!

prepare_started_epoch=$(date +%s)
./ci/prepare-central-runner.sh

wait "$device_warm_pid" || true
prepare_duration_seconds=$(($(date +%s) - prepare_started_epoch))
device_warm_finished_epoch=$(cat "$device_warm_finished_epoch_file")
device_warm_duration_seconds=$((device_warm_finished_epoch - device_warm_started_epoch))

set +e
wait "$preflight_pid"
preflight_status=$?
set -e
preflight_finished_epoch=$(cat "$preflight_finished_epoch_file")
preflight_duration_seconds=$((preflight_finished_epoch - preflight_started_epoch))

{
  echo "started_epoch=$workflow_started_epoch"
  echo "preflight_duration_seconds=$preflight_duration_seconds"
  echo "duration_seconds=$prepare_duration_seconds"
  echo "device_warm_duration_seconds=$device_warm_duration_seconds"
} >> "$GITHUB_OUTPUT"

if ((preflight_status != 0)); then
  echo "Repository preflight failed with exit code $preflight_status." >&2
  exit "$preflight_status"
fi
