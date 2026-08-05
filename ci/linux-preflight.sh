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
