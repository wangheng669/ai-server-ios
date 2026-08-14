#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == --stdin ]]; then
  diff_input=$(cat)
elif (($# == 2)); then
  while IFS= read -r changed_path; do
    case "$changed_path" in
      AIClient/*.swift|AIClient/**/*.swift) ;;
      *) exit 1 ;;
    esac
  done < <(git diff --name-only "$1"..."$2")
  diff_input=$(git diff --unified=0 --no-ext-diff "$1"..."$2" -- '*.swift')
else
  echo "usage: is-low-risk-ios-diff.sh BASE HEAD | --stdin" >&2
  exit 2
fi

LOW_RISK_DIFF_INPUT="$diff_input" python3 - <<'PY'
import os
import re
import sys

diff = os.environ.get("LOW_RISK_DIFF_INPUT", "")
if not diff.strip():
    sys.exit(1)

pattern = re.compile(
    r'^(?P<prefix>\s*(?:private\s+)?static\s+let\s+'
    r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"[^"]*\.v)'
    r'(?P<version>[0-9]+)(?P<suffix>"\s*)$'
)

hunks = []
removed = []
added = []

def flush():
    global removed, added
    if removed or added:
        hunks.append((removed, added))
    removed = []
    added = []

for line in diff.splitlines():
    if line.startswith("@@"):
        flush()
    elif line.startswith("---") or line.startswith("+++"):
        continue
    elif line.startswith("-"):
        removed.append(line[1:])
    elif line.startswith("+"):
        added.append(line[1:])
flush()

if not hunks:
    sys.exit(1)

for old_lines, new_lines in hunks:
    if len(old_lines) != len(new_lines) or not old_lines:
        sys.exit(1)
    for old, new in zip(old_lines, new_lines):
        old_match = pattern.fullmatch(old)
        new_match = pattern.fullmatch(new)
        if not old_match or not new_match:
            sys.exit(1)
        name = old_match.group("name").lower()
        if not any(token in name for token in ("cache", "key", "version", "schema")):
            sys.exit(1)
        if old_match.group("prefix") != new_match.group("prefix"):
            sys.exit(1)
        if old_match.group("suffix") != new_match.group("suffix"):
            sys.exit(1)
        if old_match.group("version") == new_match.group("version"):
            sys.exit(1)
PY
