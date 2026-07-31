#!/bin/bash

set -uo pipefail

mode="${1:-}"
repo_slug="wangheng669/ai-server-ios"
retry_seconds="${TESTFLIGHT_TRIGGER_RETRY_SECONDS:-300}"
timeout_seconds="${TESTFLIGHT_TRIGGER_TIMEOUT_SECONDS:-43200}"
started_at="$(date +%s)"

if [[ -x /opt/homebrew/bin/gh ]]; then
  gh_bin="/opt/homebrew/bin/gh"
else
  gh_bin="$(command -v gh || true)"
fi

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

if [[ -z "$gh_bin" ]]; then
  log "GitHub CLI is not installed."
  exit 1
fi

if [[ "$mode" == "--dry-run" ]]; then
  "$gh_bin" auth status --hostname github.com
  "$gh_bin" workflow view testflight.yml --repo "$repo_slug" >/dev/null
  log "Dry run passed. The local task can reach GitHub and authenticate."
  log "Scheduled command: gh workflow run testflight.yml --ref main -f git_ref=main -f only_if_new=true"
  exit 0
fi

attempt=0
while true; do
  attempt=$((attempt + 1))
  log "Trigger attempt $attempt for the daily TestFlight upload."
  if "$gh_bin" workflow run testflight.yml \
    --repo "$repo_slug" \
    --ref main \
    -f git_ref=main \
    -f only_if_new=true; then
    log "GitHub accepted the daily TestFlight trigger."
    exit 0
  fi

  elapsed=$(( $(date +%s) - started_at ))
  if (( elapsed >= timeout_seconds )); then
    log "Giving up after ${elapsed} seconds without a successful GitHub response."
    exit 1
  fi

  log "GitHub is unavailable; retrying in ${retry_seconds} seconds."
  sleep "$retry_seconds"
done
