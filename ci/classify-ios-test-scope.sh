#!/usr/bin/env bash
set -euo pipefail

app_changed=false
feed_only=true
while IFS= read -r changed_path; do
  case "$changed_path" in
    ci/sign-and-install-ios.sh|ci/prepare-central-runner-parallel.sh|ci/report-ios-deployment.sh)
      app_changed=true
      feed_only=false
      ;;
    .github/*|ci/*|*.md) ;;
    AIClient/Features/Feed/*|AIClientTests/FeedAdapterTests.swift)
      app_changed=true
      ;;
    *)
      app_changed=true
      feed_only=false
      ;;
  esac
done

test_scope=none
if [[ "$app_changed" == true ]]; then
  test_scope=full
  if [[ "$feed_only" == true ]]; then
    test_scope=feed
  fi
fi

printf 'app_changed=%s\ntest_scope=%s\n' "$app_changed" "$test_scope"
