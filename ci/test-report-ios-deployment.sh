#!/usr/bin/env bash
set -euo pipefail

test_root=$(mktemp -d "${TMPDIR:-/tmp}/ios-deployment-report-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"

cat >"$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
  if [[ "$1" == --data ]]; then
    printf '%s' "$2" >"$IOS_TEST_PAYLOAD"
    shift 2
    continue
  fi
  shift
done
printf '200'
EOF
chmod +x "$test_root/bin/curl"

PATH="$test_root/bin:$PATH" \
DEPLOYMENT_STATUS_API_KEY=test \
IOS_TEST_PAYLOAD="$test_root/payload.json" \
IOS_DEPLOYMENT_COMMIT=1234567890abcdef1234567890abcdef12345678 \
IOS_DEPLOYMENT_SOURCE_BRANCH=codex/test \
IOS_DEPLOYMENT_RUN_ID=42 \
IOS_DELIVERY_MODE=local-fallback \
IOS_DEVICE_ID=DEVICE \
IOS_DEVICE_NAME='Test iPhone' \
  ./ci/report-ios-deployment.sh succeeded 1 installed-local-fallback

jq -e '
  .deliveryMode == "local-fallback" and
  .deviceId == "DEVICE" and
  .deviceName == "Test iPhone" and
  .acceptance == "accepted" and
  (.installedAt | length > 0) and
  (.acceptedAt == .installedAt)
' "$test_root/payload.json" >/dev/null

echo 'iOS deployment metadata report test passed.'
