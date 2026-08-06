#!/usr/bin/env bash
set -euo pipefail

classify() {
  printf '%s\n' "$@" | ./ci/classify-ios-test-scope.sh
}

[[ "$(classify docs/README.md .github/workflows/example.yml)" == $'app_changed=false\ntest_scope=none' ]]
[[ "$(classify AIClient/Features/Feed/NewsFeedView.swift AIClientTests/FeedAdapterTests.swift)" == $'app_changed=true\ntest_scope=feed' ]]
[[ "$(classify AIClient/Core/APIClient.swift)" == $'app_changed=true\ntest_scope=full' ]]
[[ "$(classify AIClient/Features/Feed/NewsFeedView.swift AIClient/Core/APIClient.swift)" == $'app_changed=true\ntest_scope=full' ]]

echo "iOS test scope classifier passed."
