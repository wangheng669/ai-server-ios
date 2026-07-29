#!/bin/bash

set -euo pipefail

: "${APP_ARCHIVE:?APP_ARCHIVE is required}"
: "${APP_PATH:?APP_PATH is required}"
: "${BUNDLE_ID:?BUNDLE_ID is required}"
: "${TEAM_ID:?TEAM_ID is required}"
: "${DEVICE_UDID:?DEVICE_UDID is required}"

# Self-hosted runners do not always inherit the interactive login session's
# unlocked keychain state. The office installer uses an empty local keychain
# password, so unlock it explicitly before accessing the signing private key.
# On hosts with a different keychain password this is a harmless no-op.
security unlock-keychain -p "${IOS_KEYCHAIN_PASSWORD:-}" \
  "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true

device_attempts=${IOS_DEVICE_WAIT_ATTEMPTS:-12}
device_wait_seconds=${IOS_DEVICE_WAIT_SECONDS:-5}
device_available=false

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
  local max_attempts=${IOS_INSTALL_ATTEMPTS:-6}
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
  refreshed_derived_data="$RUNNER_TEMP/AIServerClient-RefreshedSigning"
  xcodebuild build \
    -project AIServerClient.xcodeproj \
    -scheme AIServerClient \
    -configuration Debug \
    -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$refreshed_derived_data" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic

  refreshed_app="$refreshed_derived_data/Build/Products/Debug-iphoneos/AIServerClient.app"
  test -d "$refreshed_app"
  codesign --verify --deep --strict --verbose=2 "$refreshed_app"
  if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
    ./ci/report-ios-deployment.sh running 0.92 installing || true
  fi
  install_app_with_connectivity_retry "$refreshed_app"
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

if find "$APP_PATH" -type d -name '*.appex' -print -quit | grep -q .; then
  echo "App extensions require their own provisioning profiles and are not supported by this installer yet." >&2
  exit 1
fi

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
  ./ci/report-ios-deployment.sh running 0.92 installing || true
fi
installation_description="profile valid until $selected_expiration"

if ! install_app_with_connectivity_retry "$APP_PATH"; then
  if ! grep -Fq "identity used to sign the executable is no longer valid" "$install_log"; then
    exit 1
  fi

  echo "The device rejected the cached signing identity; refreshing signing assets with Xcode."
  refreshed_derived_data="$RUNNER_TEMP/AIServerClient-RefreshedSigning"
  xcodebuild build \
    -project AIServerClient.xcodeproj \
    -scheme AIServerClient \
    -configuration Debug \
    -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$refreshed_derived_data" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic

  refreshed_app="$refreshed_derived_data/Build/Products/Debug-iphoneos/AIServerClient.app"
  test -d "$refreshed_app"
  codesign --verify --deep --strict --verbose=2 "$refreshed_app"
  install_app_with_connectivity_retry "$refreshed_app"
  installation_description="Xcode-refreshed automatic signing"
fi

echo "Installed $BUNDLE_ID on $DEVICE_UDID using $installation_description."
