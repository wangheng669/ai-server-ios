#!/usr/bin/env bash
set -euo pipefail

cache_root=${IOS_BUILD_CACHE_ROOT:-${RUNNER_TOOL_CACHE:-/tmp}/ai-server-ios}
mkdir -p "$cache_root"

# Compile verification does not require a signing identity or attached phone.
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
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO
  app_path="$cache_root/central-merge-signing/Build/Products/Debug-iphoneos/AIServerClient.app"
  test -d "$app_path"
  ditto -c -k --sequesterRsrc --keepParent \
    "$app_path" "$prebuilt_dir/AIServerClient.app.zip"
  git rev-parse HEAD > "$prebuilt_dir/source-sha"
) &
device_pid=$!

set +e
wait "$device_pid"
device_status=$?
device_seconds=$(($(date +%s) - device_started_epoch))
set -e

echo "Dependency resolution completed in ${dependency_seconds}s."
echo "Device build cache warm completed in ${device_seconds}s (exit $device_status)."

if [[ -n "${IOS_PREPARE_METRICS_FILE:-}" ]]; then
  {
    echo "dependency_seconds=$dependency_seconds"
    echo "device_build_warm_seconds=$device_seconds"
  } > "$IOS_PREPARE_METRICS_FILE"
fi

if ((device_status != 0)); then
  exit "$device_status"
fi
