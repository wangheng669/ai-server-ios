#!/bin/bash

set -euo pipefail

mode="${1:-}"
support_dir="$HOME/Library/Application Support/ai-server-ios"
credentials_dir="$support_dir/credentials"
credentials_file="$credentials_dir/release.env"
private_key_path="$credentials_dir/AuthKey.p8"
mirror_dir="$support_dir/repository.git"
state_dir="$support_dir/state"
last_success_file="$state_dir/last-successful-main-sha"
work_root="$support_dir/work"
repo_url="https://github.com/wangheng669/ai-server-ios.git"
developer_dir="/Applications/Xcode-beta.app/Contents/Developer"
expected_xcode_build="27A5228h"
run_lock="/tmp/ai-server-ios-local-testflight.lock"
run_lock_owner="$run_lock/pid"
retry_seconds="${TESTFLIGHT_SYNC_RETRY_SECONDS:-300}"
timeout_seconds="${TESTFLIGHT_SYNC_TIMEOUT_SECONDS:-43200}"
started_at="$(date +%s)"
work_dir=""

timestamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

cleanup() {
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    rm -rf "$work_dir"
  fi
  if [[ -f "$run_lock_owner" ]] &&
    [[ "$(tr -d '[:space:]' < "$run_lock_owner")" == "$$" ]]; then
    rm -f "$run_lock_owner"
    rmdir "$run_lock" 2>/dev/null || true
  fi
}

require_local_credentials() {
  if [[ ! -s "$credentials_file" || ! -s "$private_key_path" ]]; then
    log "Local App Store Connect credentials are not installed."
    return 1
  fi
  # The file is generated locally with simple key=value entries and mode 0600.
  # shellcheck disable=SC1090
  source "$credentials_file"
  : "${APP_STORE_CONNECT_KEY_ID:?missing APP_STORE_CONNECT_KEY_ID}"
  : "${APP_STORE_CONNECT_ISSUER_ID:?missing APP_STORE_CONNECT_ISSUER_ID}"
  : "${DEPLOYMENT_STATUS_API_KEY:?missing DEPLOYMENT_STATUS_API_KEY}"
  export APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID
  export DEPLOYMENT_STATUS_API_KEY
}

verify_xcode() {
  local actual_build
  test -x "$developer_dir/usr/bin/xcodebuild"
  actual_build="$(
    plutil -extract ProductBuildVersion raw -o - \
      "$developer_dir/../version.plist"
  )"
  if [[ "$actual_build" != "$expected_xcode_build" ]]; then
    log "Expected Xcode build $expected_xcode_build, found $actual_build."
    return 1
  fi
}

sync_main() {
  if [[ ! -d "$mirror_dir" ]]; then
    git clone --mirror "$repo_url" "$mirror_dir"
  else
    git --git-dir="$mirror_dir" fetch --prune origin \
      '+refs/heads/main:refs/heads/main'
  fi
  git --git-dir="$mirror_dir" rev-parse refs/heads/main
}

if ! mkdir "$run_lock" 2>/dev/null; then
  existing_pid=""
  if [[ -f "$run_lock_owner" ]]; then
    existing_pid="$(tr -d '[:space:]' < "$run_lock_owner")"
  fi
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    log "Another local TestFlight release is already running as pid $existing_pid."
    exit 0
  fi
  log "Recovering a stale local TestFlight lock."
  rm -f "$run_lock_owner"
  rmdir "$run_lock"
  mkdir "$run_lock"
fi
printf '%s\n' "$$" > "$run_lock_owner"
trap cleanup EXIT INT TERM

umask 077
mkdir -p "$state_dir" "$work_root"
require_local_credentials
verify_xcode

if [[ "$mode" == "--dry-run" ]]; then
  git ls-remote --exit-code "$repo_url" refs/heads/main >/dev/null
  log "Dry run passed. Local credentials, Xcode, and main source are available."
  exit 0
fi

attempt=0
while true; do
  attempt=$((attempt + 1))
  log "Sync attempt $attempt for origin/main."
  if main_sha="$(sync_main)"; then
    break
  fi
  elapsed=$(( $(date +%s) - started_at ))
  if (( elapsed >= timeout_seconds )); then
    log "Giving up after ${elapsed} seconds without syncing origin/main."
    exit 1
  fi
  log "GitHub source sync is unavailable; retrying in ${retry_seconds} seconds."
  sleep "$retry_seconds"
done

if [[ -f "$last_success_file" ]] &&
  [[ "$(tr -d '[:space:]' < "$last_success_file")" == "$main_sha" ]]; then
  log "Skipping $main_sha; this main revision was already uploaded successfully."
  exit 0
fi

work_dir="$(mktemp -d "$work_root/release.XXXXXX")"
git --git-dir="$mirror_dir" archive "$main_sha" | tar -x -C "$work_dir"
cd "$work_dir"

export DEVELOPER_DIR="$developer_dir"
export GITHUB_SHA="$main_sha"
GITHUB_RUN_ID="local-$(date +%Y%m%d%H%M%S)"
export GITHUB_RUN_ID
export GITHUB_SERVER_URL="https://github.com"
export GITHUB_REPOSITORY="wangheng669/ai-server-ios"
export GITHUB_RUN_URL="local://$GITHUB_RUN_ID"
builds_before="$work_dir/TestFlightBuildsBeforeUpload.json"
archive_path="$work_dir/AIServerClient.xcarchive"
export_path="$work_dir/TestFlightExport"

log "Preparing the next TestFlight version from main $main_sha."
TESTFLIGHT_BASE_MARKETING_VERSION="$(
  plutil -extract CFBundleShortVersionString raw -o - Config/Info.plist
)"
export TESTFLIGHT_BASE_MARKETING_VERSION
ruby ci/testflight-processing-notify.rb prepare "$builds_before"
plutil -replace CFBundleShortVersionString \
  -string "$TESTFLIGHT_MARKETING_VERSION" Config/Info.plist

log "Running tests for TestFlight $TESTFLIGHT_MARKETING_VERSION."
./ci/with-ios-simulator-lock.sh \
  --label "Local TestFlight $GITHUB_RUN_ID" \
  -- xcodebuild test \
  -project AIServerClient.xcodeproj \
  -scheme AIServerClient \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -derivedDataPath "$work_dir/TestDerivedData" \
  CODE_SIGNING_ALLOWED=NO

log "Creating the signed App Store archive."
xcodebuild archive \
  -project AIServerClient.xcodeproj \
  -scheme AIServerClient \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$private_key_path" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  DEVELOPMENT_TEAM=9M7P4VLHY3 \
  CODE_SIGN_STYLE=Automatic

log "Uploading the archive directly from this Mac."
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist ci/ExportOptions-TestFlight.plist \
  -exportPath "$export_path" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$private_key_path" \
  -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"

log "Waiting for Apple processing and DingTalk notification."
ruby ci/testflight-processing-notify.rb wait "$builds_before"
printf '%s\n' "$main_sha" > "$last_success_file"
log "Local TestFlight release completed successfully for $main_sha."
