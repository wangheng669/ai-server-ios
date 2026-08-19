#!/usr/bin/env bash
set -euo pipefail

cache_root=${IOS_BUILD_CACHE_ROOT:-${RUNNER_TOOL_CACHE:-/tmp}/ai-server-ios}
mkdir -p "$cache_root"

# LaunchAgent runners do not inherit the interactive user's unlocked keychain
# state. Unlock before the prewarmed signed build so codesign can access the
# selected Apple Development identity.
security unlock-keychain -p "${IOS_KEYCHAIN_PASSWORD:-}" \
  "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true

xcodebuild -version
dependency_started_epoch=$(date +%s)
xcodebuild -resolvePackageDependencies \
  -project AIServerClient.xcodeproj \
  -scheme AIServerClient \
  -clonedSourcePackagesDirPath "$cache_root/source-packages"
dependency_seconds=$(($(date +%s) - dependency_started_epoch))

device_started_epoch=$(date +%s)
(
  prebuilt_dir="$cache_root/central-merge-signing/prewarmed"
  mkdir -p "$prebuilt_dir"
  rm -f "$prebuilt_dir/AIServerClient.app.zip" "$prebuilt_dir/source-sha"
  xcodebuild build \
    -project AIServerClient.xcodeproj \
    -scheme AIServerClient \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$cache_root/central-merge-signing" \
    -clonedSourcePackagesDirPath "$cache_root/source-packages" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="${TEAM_ID:?TEAM_ID is required}" \
    CODE_SIGN_STYLE=Automatic
  app_path="$cache_root/central-merge-signing/Build/Products/Debug-iphoneos/AIServerClient.app"
  codesign --verify --deep --strict --verbose=2 "$app_path"
  ditto -c -k --sequesterRsrc --keepParent \
    "$app_path" "$prebuilt_dir/AIServerClient.app.zip"
  git rev-parse HEAD > "$prebuilt_dir/source-sha"
) &
device_pid=$!

simulator_seconds=0
simulator_status=0
simulator_pid=
if [[ "${IOS_SKIP_SIMULATOR_WARM:-false}" != true ]]; then
  simulator_started_epoch=$(date +%s)
  (
    ./ci/with-ios-simulator-lock.sh \
      --label "central cache warm ${GITHUB_RUN_ID:-local}" \
      --wait-seconds 1200 \
      -- bash -c '
        set -euo pipefail
        xcrun simctl boot "iPhone 16e" 2>/dev/null || true
        xcrun simctl bootstatus "iPhone 16e" -b
      '
    # Compilation uses isolated DerivedData and does not install or launch the
    # test runner, so it must not extend the shared simulator reservation.
    xcodebuild build-for-testing \
      -project AIServerClient.xcodeproj \
      -scheme AIServerClient \
      -destination "platform=iOS Simulator,name=iPhone 16e" \
      -derivedDataPath "$cache_root/central-merge-simulator" \
      -clonedSourcePackagesDirPath "$cache_root/source-packages" \
      CODE_SIGNING_ALLOWED=NO
  ) &
  simulator_pid=$!
else
  echo "Low-risk App change; skipping shared simulator cache warm."
fi

set +e
wait "$device_pid"
device_status=$?
device_seconds=$(($(date +%s) - device_started_epoch))
if [[ -n "$simulator_pid" ]]; then
  wait "$simulator_pid"
  simulator_status=$?
  simulator_seconds=$(($(date +%s) - simulator_started_epoch))
fi
set -e

echo "Dependency resolution completed in ${dependency_seconds}s."
echo "Device build cache warm completed in ${device_seconds}s (exit $device_status)."
echo "Simulator boot and test cache warm completed in ${simulator_seconds}s (exit $simulator_status)."

if [[ -n "${IOS_PREPARE_METRICS_FILE:-}" ]]; then
  {
    echo "dependency_seconds=$dependency_seconds"
    echo "device_build_warm_seconds=$device_seconds"
    echo "simulator_warm_seconds=$simulator_seconds"
  } > "$IOS_PREPARE_METRICS_FILE"
fi

if ((device_status != 0)); then
  exit "$device_status"
fi
if ((simulator_status != 0)); then
  exit "$simulator_status"
fi

if [[ "${IOS_SKIP_SIMULATOR_WARM:-false}" != true ]]; then
  # The merge job may reuse this exact build-for-testing output when the merged
  # tree is byte-for-byte identical to the task commit that produced it.
  git rev-parse HEAD > "$cache_root/central-merge-simulator/prewarmed-source-sha"
fi
