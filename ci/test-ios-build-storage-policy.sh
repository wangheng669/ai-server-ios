#!/usr/bin/env bash
set -euo pipefail

if git ls-files '.derived-data-reference/**' | grep -q .; then
  echo '.derived-data-reference must never be tracked by Git.' >&2
  exit 1
fi

for pattern in \
  '.derived-data-reference/' \
  '.xcodebuildmcp/' \
  '*.xcresult' \
  '*.app.zip' \
  '*.ipa' \
  '*.dSYM/'; do
  grep -Fxq "$pattern" .gitignore || {
    echo "Missing build-product ignore rule: $pattern" >&2
    exit 1
  }
done

build_commands=$(
  rg -n --hidden 'xcodebuild (build|test|archive|build-for-testing|"\$[A-Za-z_][A-Za-z0-9_]*")' \
    ci .github/workflows -g '!test-ios-build-storage-policy.sh' \
    | wc -l | tr -d '[:space:]'
)
index_disabled=$(
  rg -n --hidden 'COMPILER_INDEX_STORE_ENABLE=NO' \
    ci .github/workflows -g '!test-ios-build-storage-policy.sh' \
    | wc -l | tr -d '[:space:]'
)
if [[ "$build_commands" != "$index_disabled" ]]; then
  echo "Every automated Xcode build must disable index storage ($build_commands builds, $index_disabled settings)." >&2
  exit 1
fi

grep -Fq 'prune-ios-install-deltas.sh" --apply' ci/sign-and-install-ios.sh
echo 'iOS build storage policy checks passed.'
