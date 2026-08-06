#!/usr/bin/env bash
set -euo pipefail

cache_root=${IOS_BUILD_CACHE_ROOT:-${RUNNER_TOOL_CACHE:-/tmp}/ai-server-ios}
mkdir -p "$cache_root"

xcodebuild -version
dependency_started_epoch=$(date +%s)
xcodebuild -resolvePackageDependencies \
  -project AIServerClient.xcodeproj \
  -scheme AIServerClient \
  -clonedSourcePackagesDirPath "$cache_root/source-packages"
dependency_seconds=$(($(date +%s) - dependency_started_epoch))

device_started_epoch=$(date +%s)
(
  xcodebuild build \
    -project AIServerClient.xcodeproj \
    -scheme AIServerClient \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$cache_root/central-merge-signing" \
    -clonedSourcePackagesDirPath "$cache_root/source-packages" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
) &
device_pid=$!

simulator_started_epoch=$(date +%s)
(
  # The inner script intentionally expands its positional parameters in the
  # child shell rather than in this parent process.
  # shellcheck disable=SC2016
  ./ci/with-ios-simulator-lock.sh \
    --label "central cache warm ${GITHUB_RUN_ID:-local}" \
    -- bash -c '
      set -euo pipefail
      xcrun simctl boot "iPhone 16e" 2>/dev/null || true
      xcrun simctl bootstatus "iPhone 16e" -b
      xcodebuild build-for-testing \
        -project AIServerClient.xcodeproj \
        -scheme AIServerClient \
        -destination "platform=iOS Simulator,name=iPhone 16e" \
        -derivedDataPath "$1/central-merge-simulator" \
        -clonedSourcePackagesDirPath "$1/source-packages" \
        CODE_SIGNING_ALLOWED=NO
    ' _ "$cache_root"
) &
simulator_pid=$!

set +e
wait "$device_pid"
device_status=$?
device_seconds=$(($(date +%s) - device_started_epoch))
wait "$simulator_pid"
simulator_status=$?
simulator_seconds=$(($(date +%s) - simulator_started_epoch))
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

# The merge job may reuse this exact build-for-testing output when the merged
# tree is byte-for-byte identical to the task commit that produced it.
git rev-parse HEAD > "$cache_root/central-merge-simulator/prewarmed-source-sha"
