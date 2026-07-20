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

if ! xcrun devicectl device info details --device "$DEVICE_UDID" >/dev/null 2>&1; then
  echo "The configured iPhone is not connected or available: $DEVICE_UDID" >&2
  exit 1
fi

install_root=$(dirname "$APP_PATH")
mkdir -p "$install_root"
ditto -x -k "$APP_ARCHIVE" "$install_root"
test -d "$APP_PATH"

expected_application_id="$TEAM_ID.$BUNDLE_ID"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
selected_profile=""
selected_expiration=""
decoded_profile=$(mktemp "$RUNNER_TEMP/profile.XXXXXX")
entitlements=$(mktemp "$RUNNER_TEMP/entitlements.XXXXXX")
profile_certificate=$(mktemp "$RUNNER_TEMP/profile-certificate.XXXXXX")

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

  if [[ -z "$selected_expiration" || "$expiration" > "$selected_expiration" ]]; then
    selected_profile="$profile"
    selected_expiration="$expiration"
  fi
done < <(find "${profile_roots[@]}" -type f -name '*.mobileprovision' -print 2>/dev/null)

if [[ -z "$selected_profile" ]]; then
  echo "No current provisioning profile matches $BUNDLE_ID and device $DEVICE_UDID." >&2
  echo "Open the project in Xcode and run it once on the iPhone to refresh free signing." >&2
  exit 1
fi

security cms -D -i "$selected_profile" > "$decoded_profile" 2>/dev/null
plutil -extract Entitlements xml1 -o "$entitlements" "$decoded_profile"
cp "$selected_profile" "$APP_PATH/embedded.mobileprovision"

plutil -extract DeveloperCertificates.0 raw -o - "$decoded_profile" | base64 -D -o "$profile_certificate"
signing_identity=$(
  openssl x509 -inform DER -in "$profile_certificate" -noout -fingerprint -sha1 \
    | awk -F= '{gsub(":", "", $2); print toupper($2)}'
)

if ! security find-identity -v -p codesigning | grep -Fq "$signing_identity"; then
  echo "The signing certificate required by the provisioning profile is not available with its private key." >&2
  echo "Open the project in Xcode and run it once on the iPhone to refresh free signing." >&2
  exit 1
fi

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
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"

echo "Installed $BUNDLE_ID on $DEVICE_UDID using a profile valid until $selected_expiration."
