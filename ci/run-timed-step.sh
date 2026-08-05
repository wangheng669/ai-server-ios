#!/usr/bin/env bash

set -uo pipefail

label=${1:?step label is required}
shift
if (($# == 0)); then
  echo "command is required" >&2
  exit 2
fi

started_at=$(date +%s)
set +e
"$@"
status=$?
set -e
finished_at=$(date +%s)
duration=$((finished_at - started_at))
minutes=$((duration / 60))
seconds=$((duration % 60))

echo "$label completed in ${minutes}m ${seconds}s (exit $status)."
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  result=success
  if ((status != 0)); then
    result=failure
  fi
  printf '| %s | %dm %ds | %s |\n' "$label" "$minutes" "$seconds" "$result" >> "$GITHUB_STEP_SUMMARY"
fi

exit "$status"
