#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-origin/main}"

if [[ "${IOS_PREFLIGHT_SKIP_FETCH:-false}" != true ]]; then
  git fetch --no-tags origin main:refs/remotes/origin/main
fi
merge_base="$(git merge-base "$base_ref" HEAD)"

echo "Checking task changes since $merge_base"
git diff --check "$merge_base"...HEAD

if git diff --unified=0 "$merge_base"...HEAD -- ':!*.md' \
  | grep -E '^\+(<<<<<<<|=======|>>>>>>>)'; then
  echo "Unresolved merge markers found." >&2
  exit 1
fi

changed_shell_files=()
while IFS= read -r path; do
  changed_shell_files+=("$path")
done < <(git diff --name-only --diff-filter=ACMR "$merge_base"...HEAD -- '*.sh')
if ((${#changed_shell_files[@]})); then
  printf 'Checking shell scripts:\n'
  printf '  %s\n' "${changed_shell_files[@]}"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${changed_shell_files[@]}"
  else
    for path in "${changed_shell_files[@]}"; do
      bash -n "$path"
    done
  fi
fi

if git diff --name-only "$merge_base"...HEAD -- ci/sign-and-install-ios.sh ci/test-sign-and-install-ios.sh | grep -q .; then
  bash ci/test-sign-and-install-ios.sh
fi

if git diff --name-only "$merge_base"...HEAD -- ci/classify-ios-test-scope.sh ci/is-low-risk-ios-diff.sh ci/test-classify-ios-test-scope.sh .github/workflows/ai-merge-to-main.yml | grep -q .; then
  bash ci/test-classify-ios-test-scope.sh
fi

if git diff --name-only "$merge_base"...HEAD -- ci/verify-ios-device-stability.sh ci/test-verify-ios-device-stability.sh ci/probe-ios-device.sh .github/workflows/ai-merge-to-main.yml | grep -q .; then
  bash ci/test-verify-ios-device-stability.sh
fi

if git diff --name-only "$merge_base"...HEAD -- ci/prepare-central-runner-parallel.sh ci/test-central-device-delivery-policy.sh .github/workflows/ai-merge-to-main.yml | grep -q .; then
  bash ci/test-central-device-delivery-policy.sh
fi

if git diff --name-only "$merge_base"...HEAD -- ci/local-central-merge.sh ci/actions-outage-fallback-watch.sh | grep -q .; then
  bash ci/test-actions-outage-fallback-watch.sh
fi

if git diff --name-only "$merge_base"...HEAD -- ci/with-ios-simulator-lock.sh ci/test-with-ios-simulator-lock.sh | grep -q .; then
  bash ci/test-with-ios-simulator-lock.sh
fi

if python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 - <<'PY'
from pathlib import Path
import yaml

for path in sorted(Path('.github/workflows').glob('*.yml')):
    with path.open(encoding='utf-8') as handle:
        yaml.safe_load(handle)
print('Workflow YAML parsed successfully.')
PY
elif command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; Dir[".github/workflows/*.yml"].sort.each { |path| YAML.parse_file(path) }; puts "Workflow YAML parsed successfully."'
else
  echo "No YAML parser is available (install PyYAML or Ruby)." >&2
  exit 1
fi

echo "Linux preflight completed. Xcode tests remain on the selected central Mac."
