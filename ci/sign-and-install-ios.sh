#!/bin/bash

set -euo pipefail

: "${APP_ARCHIVE:?APP_ARCHIVE is required}"
: "${APP_PATH:?APP_PATH is required}"
: "${BUNDLE_ID:?BUNDLE_ID is required}"
: "${TEAM_ID:?TEAM_ID is required}"
: "${DEVICE_UDID:?DEVICE_UDID is required}"

device_wait_duration_seconds=0
direct_install_seconds=0
xcode_recovery_seconds=0
final_install_seconds=0

sync_metrics_env() {
  export IOS_DEVICE_WAIT_DURATION_SECONDS="$device_wait_duration_seconds"
  export IOS_DIRECT_INSTALL_SECONDS="$direct_install_seconds"
  export IOS_XCODE_RECOVERY_SECONDS="$xcode_recovery_seconds"
  export IOS_FINAL_INSTALL_SECONDS="$final_install_seconds"
}

write_metrics() {
  sync_metrics_env
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'device_wait_seconds=%s\ndirect_install_seconds=%s\nxcode_recovery_seconds=%s\nfinal_install_seconds=%s\n' \
      "$device_wait_duration_seconds" "$direct_install_seconds" "$xcode_recovery_seconds" "$final_install_seconds" >> "$GITHUB_OUTPUT"
  fi
}
trap write_metrics EXIT

# Self-hosted runners do not always inherit the interactive login session's
# unlocked keychain state. The office installer uses an empty local keychain
# password, so unlock it explicitly before accessing the signing private key.
# On hosts with a different keychain password this is a harmless no-op.
security unlock-keychain -p "${IOS_KEYCHAIN_PASSWORD:-}" \
  "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true

device_attempts=${IOS_DEVICE_WAIT_ATTEMPTS:-12}
device_wait_seconds=${IOS_DEVICE_WAIT_SECONDS:-5}
device_available=false
device_wait_started_epoch=$(date +%s)

if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
  ./ci/report-ios-deployment.sh running 0.82 checking-device || true
fi

for ((attempt = 1; attempt <= device_attempts; attempt++)); do
  if xcrun devicectl device info details --device "$DEVICE_UDID" >/dev/null 2>&1; then
    device_available=true
    echo "iPhone is available (attempt $attempt/$device_attempts)."
    break
  fi

  if [[ "$attempt" -lt "$device_attempts" ]]; then
    echo "Waiting for iPhone $DEVICE_UDID (attempt $attempt/$device_attempts)..."
    if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
      ./ci/report-ios-deployment.sh running 0.86 waiting-for-device || true
    fi
    sleep "$device_wait_seconds"
  fi
done
device_wait_duration_seconds=$(($(date +%s) - device_wait_started_epoch))
sync_metrics_env

if [[ "$device_available" != true ]]; then
  echo "The configured iPhone did not become available after $device_attempts attempts: $DEVICE_UDID" >&2
  exit 1
fi

install_root=$(dirname "$APP_PATH")
mkdir -p "$install_root"
ditto -x -k "$APP_ARCHIVE" "$install_root"
test -d "$APP_PATH"

install_log=$(mktemp "$RUNNER_TEMP/device-install.XXXXXX")

install_app_with_connectivity_retry() {
  local candidate_app=$1
  local max_attempts=${IOS_INSTALL_ATTEMPTS:-2}
  local retry_seconds=${IOS_INSTALL_RETRY_SECONDS:-5}
  : > "$install_log"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if xcrun devicectl device install app --device "$DEVICE_UDID" "$candidate_app" 2>&1 | tee -a "$install_log"; then
      return 0
    fi
    if ! grep -Eq "CoreDeviceError error 4016|not able to fulfill the requested usage assertion" "$install_log"; then
      return 1
    fi
    if [[ "$attempt" -lt "$max_attempts" ]]; then
      echo "Trusted iPhone connection dropped during install; retrying ($attempt/$max_attempts)..."
      sleep "$retry_seconds"
    fi
  done
  return 1
}

run_direct_install() {
  local started status
  started=$(date +%s)
  if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
    ./ci/report-ios-deployment.sh running 0.88 installing-direct || true
  fi
  set +e
  install_app_with_connectivity_retry "$1"
  status=$?
  set -e
  direct_install_seconds=$((direct_install_seconds + $(date +%s) - started))
  sync_metrics_env
  return "$status"
}

run_final_install() {
  local started status
  started=$(date +%s)
  if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
    ./ci/report-ios-deployment.sh running 0.96 installing-final || true
  fi
  set +e
  install_app_with_connectivity_retry "$1"
  status=$?
  set -e
  final_install_seconds=$((final_install_seconds + $(date +%s) - started))
  sync_metrics_env
  return "$status"
}

xcode_refreshed_app=""

refresh_signing_with_xcode() {
  local refreshed_derived_data="${IOS_SIGNING_DERIVED_DATA_PATH:-$RUNNER_TEMP/AIServerClient-RefreshedSigning}"
  local build_log
  local max_attempts=${IOS_XCODE_DESTINATION_ATTEMPTS:-3}
  local retry_seconds=${IOS_XCODE_DESTINATION_RETRY_SECONDS:-5}
  local destination_timeout=${IOS_XCODE_DESTINATION_TIMEOUT_SECONDS:-30}
  build_log=$(mktemp "$RUNNER_TEMP/xcode-signing-refresh.XXXXXX")
  mkdir -p "$refreshed_derived_data"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    echo "Waiting for Xcode to finish preparing iPhone $DEVICE_UDID (attempt $attempt/$max_attempts, timeout ${destination_timeout}s)."
    : > "$build_log"
    if xcodebuild build \
      -project AIServerClient.xcodeproj \
      -scheme AIServerClient \
      -configuration Debug \
      -destination "id=$DEVICE_UDID" \
      -destination-timeout "$destination_timeout" \
      -derivedDataPath "$refreshed_derived_data" \
      -allowProvisioningUpdates \
      -allowProvisioningDeviceRegistration \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CODE_SIGN_STYLE=Automatic 2>&1 | tee "$build_log"; then
      xcode_refreshed_app="$refreshed_derived_data/Build/Products/Debug-iphoneos/AIServerClient.app"
      test -d "$xcode_refreshed_app"
      codesign --verify --deep --strict --verbose=2 "$xcode_refreshed_app"
      return 0
    fi

    if ! grep -Eq \
      "Timed out waiting for all destinations|Preparing .*Xcode will continue|Unable to find a destination matching|requested device could not be found" \
      "$build_log"; then
      return 1
    fi

    if [[ "$attempt" -lt "$max_attempts" ]]; then
      echo "Xcode is still preparing iPhone $DEVICE_UDID; retrying signing refresh after ${retry_seconds}s."
      if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
        ./ci/report-ios-deployment.sh running 0.92 recovering-xcode || true
      fi
      sleep "$retry_seconds"
    fi
  done

  return 1
}

run_xcode_recovery() {
  local started status
  started=$(date +%s)
  if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
    ./ci/report-ios-deployment.sh running 0.92 recovering-xcode || true
  fi
  set +e
  refresh_signing_with_xcode
  status=$?
  set -e
  xcode_recovery_seconds=$((xcode_recovery_seconds + $(date +%s) - started))
  sync_metrics_env
  return "$status"
}

if find "$APP_PATH" -type d -name '*.appex' -print -quit | grep -q .; then
  if codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
    echo "App and embedded extensions are already signed; installing the prepared build directly."
    if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
      ./ci/report-ios-deployment.sh running 0.88 installing-direct || true
    fi
    if run_direct_install "$APP_PATH"; then
      echo "Installed $BUNDLE_ID on $DEVICE_UDID using the prepared signed build."
      exit 0
    fi
    echo "The prepared signed build was rejected; refreshing signing with Xcode."
  else
    echo "Prepared app signature is incomplete; refreshing signing with Xcode."
  fi
  echo "App extensions detected; using Xcode automatic signing fallback for the app and every extension."
  run_xcode_recovery
  run_final_install "$xcode_refreshed_app"
  echo "Installed $BUNDLE_ID on $DEVICE_UDID using Xcode automatic signing for embedded extensions."
  exit 0
fi

expected_application_id="$TEAM_ID.$BUNDLE_ID"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
selected_profile=""
selected_expiration=""
selected_identity=""
decoded_profile=$(mktemp "$RUNNER_TEMP/profile.XXXXXX")
entitlements=$(mktemp "$RUNNER_TEMP/entitlements.XXXXXX")
profile_certificate=$(mktemp "$RUNNER_TEMP/profile-certificate.XXXXXX")
valid_identities=$(security find-identity -v -p codesigning | grep -v 'CSSMERR_' || true)

profile_roots=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

while IFS= read -r profile; do
  if ! security cms -D -i "$profile" > "$decoded_profile" 2>/dev/null; then
    continue
  fi

  application_id=$(plutil -extract Entitlements.application-identifier raw -o - "$decoded_profile" 2>/dev/null || true)
  expiration=$(plutil -extract ExpirationDate raw -o - "$decoded_profile" 2>/dev/null || true)

  if [[ "$application_id" != "$expected_application_id" || "$expiration" < "$now" ]]; then
    continue
  fi

  if ! plutil -extract ProvisionedDevices json -o - "$decoded_profile" 2>/dev/null | grep -Fq "\"$DEVICE_UDID\""; then
    continue
  fi

  if ! plutil -extract DeveloperCertificates.0 raw -o - "$decoded_profile" 2>/dev/null \
    | base64 -D -o "$profile_certificate" 2>/dev/null; then
    continue
  fi
  profile_identity=$(
    openssl x509 -inform DER -in "$profile_certificate" -noout -fingerprint -sha1 2>/dev/null \
      | awk -F= '{gsub(":", "", $2); print toupper($2)}'
  )
  if [[ -z "$profile_identity" ]] || ! grep -Fq "$profile_identity" <<< "$valid_identities"; then
    continue
  fi

  if [[ -z "$selected_expiration" || "$expiration" > "$selected_expiration" ]]; then
    selected_profile="$profile"
    selected_expiration="$expiration"
    selected_identity="$profile_identity"
  fi
done < <(find "${profile_roots[@]}" -type f -name '*.mobileprovision' -print 2>/dev/null)

if [[ -z "$selected_profile" ]]; then
  echo "No cached provisioning profile matches this iPhone; asking Xcode to refresh automatic signing."
  run_xcode_recovery
  run_final_install "$xcode_refreshed_app"
  echo "Installed $BUNDLE_ID on $DEVICE_UDID using Xcode-refreshed automatic signing."
  exit 0
fi

security cms -D -i "$selected_profile" > "$decoded_profile" 2>/dev/null
plutil -extract Entitlements xml1 -o "$entitlements" "$decoded_profile"
cp "$selected_profile" "$APP_PATH/embedded.mobileprovision"

signing_identity="$selected_identity"

if [[ -z "$signing_identity" ]] || ! grep -Fq "$signing_identity" <<< "$valid_identities"; then
  echo "The signing certificate required by the provisioning profile is not available with its private key." >&2
  echo "Open the project in Xcode and run it once on the iPhone to refresh free signing." >&2
  exit 1
fi

echo "Using valid signing identity $signing_identity with profile valid until $selected_expiration."

while IFS= read -r -d '' nested_code; do
  codesign \
    --force \
    --sign "$signing_identity" \
    --timestamp=none \
    "$nested_code"
done < <(
  find "$APP_PATH" -depth \
    \( -type f -name '*.dylib' -o -type d -name '*.framework' \) \
    -print0
)

codesign \
  --force \
  --sign "$signing_identity" \
  --entitlements "$entitlements" \
  --timestamp=none \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
  ./ci/report-ios-deployment.sh running 0.88 installing-direct || true
fi
installation_description="profile valid until $selected_expiration"

if ! run_direct_install "$APP_PATH"; then
  if ! grep -Fq "identity used to sign the executable is no longer valid" "$install_log"; then
    exit 1
  fi

  echo "The device rejected the cached signing identity; refreshing signing assets with Xcode."
  run_xcode_recovery
  run_final_install "$xcode_refreshed_app"
  installation_description="Xcode-refreshed automatic signing"
fi

echo "Installed $BUNDLE_ID on $DEVICE_UDID using $installation_description."
