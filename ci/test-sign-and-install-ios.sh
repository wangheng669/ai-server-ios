#!/usr/bin/env bash
set -euo pipefail

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/ios-sign-install-test.XXXXXX")
trap 'rm -rf "$sandbox"' EXIT
mock_bin="$sandbox/bin"
mkdir -p "$mock_bin" "$sandbox/runner" "$sandbox/signed-app"
delta_root="$sandbox/AppInstallationBinaryDeltas"
delta_bundle="$delta_root/com.example.app"
mkdir -p "$delta_bundle"
for entry in \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd; do
  mkdir "$delta_bundle/$entry"
done

cat >"$mock_bin/security" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$mock_bin/ditto" <<'EOF'
#!/usr/bin/env bash
destination=${@: -1}
mkdir -p "$destination/AIServerClient.app/PlugIns/TestExtension.appex"
EOF
cat >"$mock_bin/codesign" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$mock_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$IOS_TEST_CALLS"
exit 0
EOF
cat >"$mock_bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
echo "xcodebuild must not run for a valid prepared signature" >&2
exit 99
EOF
chmod +x "$mock_bin"/*
touch "$sandbox/app.zip"

output=$(
  PATH="$mock_bin:$PATH" \
  RUNNER_TEMP="$sandbox/runner" \
  IOS_TEST_CALLS="$sandbox/calls" \
  IOS_INSTALL_DELTA_CACHE_ROOT="$delta_root" \
  IOS_INSTALL_DELTA_CACHE_KEEP=2 \
  APP_ARCHIVE="$sandbox/app.zip" \
  APP_PATH="$sandbox/signed-app/AIServerClient.app" \
  BUNDLE_ID="com.example.app" \
  TEAM_ID="TEAM" \
  DEVICE_UDID="DEVICE" \
  bash ./ci/sign-and-install-ios.sh
)

grep -Fq "using the prepared signed build" <<<"$output"
grep -Fq "Pruned 2 old installation delta(s)" <<<"$output"
grep -Fq "device info details" "$sandbox/calls"
grep -Fq "device install app" "$sandbox/calls"
test "$(find "$delta_bundle" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')" = 2
echo "Prepared signed app fast path passed."
