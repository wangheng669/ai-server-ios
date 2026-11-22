#!/bin/bash
set -euo pipefail

repo="$HOME/Desktop/ai-server-ios"
export GIT_TERMINAL_PROMPT=0
/usr/bin/perl -e 'alarm 30; exec @ARGV or die "Cannot run Git: $!\n";' \
  /usr/bin/git -C "$repo" -c http.version=HTTP/1.1 fetch --no-tags origin \
  refs/heads/main:refs/remotes/origin/main
revision="$(/usr/bin/git -C "$repo" rev-parse refs/remotes/origin/main)"
export FOCUS_RELEASE_MAIN="$revision"
/usr/bin/git -C "$repo" show "$revision:ci/publish-direct-install.py" |
  python3 - "$@"
