#!/usr/bin/env bash
set -euo pipefail

app_changed=false
while IFS= read -r changed_path; do
  case "$changed_path" in
    ci/sign-and-install-ios.sh) app_changed=true ;;
    .github/*|ci/*|*.md) ;;
    *) app_changed=true ;;
  esac
done

printf 'app_changed=%s\n' "$app_changed"
