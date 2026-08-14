#!/usr/bin/env bash
set -euo pipefail

classify() {
  printf '%s\n' "$@" | ./ci/classify-ios-test-scope.sh
}

classify_low_risk() {
  printf '%s\n' "$@" | IOS_LOW_RISK_CHANGE=true ./ci/classify-ios-test-scope.sh
}

[[ "$(classify docs/README.md .github/workflows/example.yml)" == $'app_changed=false\ntest_scope=none' ]]
[[ "$(classify ci/prepare-central-runner.sh ci/prepare-central-runner-parallel.sh ci/report-ios-deployment.sh)" == $'app_changed=false\ntest_scope=none' ]]
[[ "$(classify ci/sign-and-install-ios.sh)" == $'app_changed=true\ntest_scope=full' ]]
[[ "$(classify AIClient/Features/Feed/NewsFeedView.swift AIClientTests/FeedAdapterTests.swift)" == $'app_changed=true\ntest_scope=feed' ]]
[[ "$(classify AIClient/Core/APIClient.swift)" == $'app_changed=true\ntest_scope=full' ]]
[[ "$(classify AIClient/Features/Feed/NewsFeedView.swift AIClient/Core/APIClient.swift)" == $'app_changed=true\ntest_scope=full' ]]
[[ "$(classify_low_risk AIClient/Features/Investment/FamousHoldingsStore.swift)" == $'app_changed=true\ntest_scope=build' ]]

cache_version_diff=$'diff --git a/Store.swift b/Store.swift\n--- a/Store.swift\n+++ b/Store.swift\n@@ -1,2 +1,2 @@\n-    private static let payloadKey = "market.cache.v1"\n-    private static let savedAtKey = "market.saved-at.v1"\n+    private static let payloadKey = "market.cache.v2"\n+    private static let savedAtKey = "market.saved-at.v2"'
printf '%s\n' "$cache_version_diff" | ./ci/is-low-risk-ios-diff.sh --stdin

logic_diff=$'diff --git a/Store.swift b/Store.swift\n--- a/Store.swift\n+++ b/Store.swift\n@@ -1 +1 @@\n-    return cached\n+    return refreshed'
if printf '%s\n' "$logic_diff" | ./ci/is-low-risk-ios-diff.sh --stdin; then
  echo "Logic change was incorrectly classified as low risk." >&2
  exit 1
fi

mixed_diff="$cache_version_diff"$'\n@@ -4 +4 @@\n-    let interval = 60\n+    let interval = 0'
if printf '%s\n' "$mixed_diff" | ./ci/is-low-risk-ios-diff.sh --stdin; then
  echo "Mixed change was incorrectly classified as low risk." >&2
  exit 1
fi

echo "iOS test scope classifier passed."
