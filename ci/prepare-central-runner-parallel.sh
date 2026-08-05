#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

workflow_started_epoch=$(date +%s)
preflight_started_epoch=$workflow_started_epoch
preflight_log=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-preflight.XXXXXX")
preflight_finished_epoch_file=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-preflight-finished.XXXXXX")

(
  set +e
  ./ci/linux-preflight.sh origin/main
  status=$?
  date +%s > "$preflight_finished_epoch_file"
  exit "$status"
) >"$preflight_log" 2>&1 &
preflight_pid=$!

prepare_started_epoch=$(date +%s)
./ci/prepare-central-runner.sh
prepare_duration_seconds=$(($(date +%s) - prepare_started_epoch))

set +e
wait "$preflight_pid"
preflight_status=$?
set -e
cat "$preflight_log"
preflight_finished_epoch=$(cat "$preflight_finished_epoch_file")
preflight_duration_seconds=$((preflight_finished_epoch - preflight_started_epoch))

{
  echo "started_epoch=$workflow_started_epoch"
  echo "preflight_duration_seconds=$preflight_duration_seconds"
  echo "duration_seconds=$prepare_duration_seconds"
} >> "$GITHUB_OUTPUT"

if ((preflight_status != 0)); then
  echo "Repository preflight failed with exit code $preflight_status." >&2
  exit "$preflight_status"
fi
