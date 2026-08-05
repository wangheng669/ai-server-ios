#!/usr/bin/env bash
set -euo pipefail

cache_root=${IOS_BUILD_CACHE_ROOT:-${RUNNER_TOOL_CACHE:-/tmp}/ai-server-ios}
mkdir -p "$cache_root"

xcodebuild -version
xcodebuild -resolvePackageDependencies \
  -project AIServerClient.xcodeproj \
  -scheme AIServerClient \
  -clonedSourcePackagesDirPath "$cache_root/source-packages"

xcodebuild build \
  -project AIServerClient.xcodeproj \
  -scheme AIServerClient \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$cache_root/central-merge-device" \
  -clonedSourcePackagesDirPath "$cache_root/source-packages" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
