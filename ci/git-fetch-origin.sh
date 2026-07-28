#!/bin/bash

set -euo pipefail

timeout_seconds="${GIT_FETCH_TIMEOUT_SECONDS:-45}"
max_attempts="${GIT_FETCH_MAX_ATTEMPTS:-3}"

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  if GIT_TERMINAL_PROMPT=0 /usr/bin/perl -e '
    my $timeout = shift @ARGV;
    alarm $timeout;
    exec @ARGV;
    die "Unable to execute Git: $!\n";
  ' \
    "$timeout_seconds" \
    git \
    -c http.version=HTTP/1.1 \
    -c http.lowSpeedLimit=1 \
    -c http.lowSpeedTime=30 \
    fetch "$@"; then
    exit 0
  fi

  if [[ "$attempt" == "$max_attempts" ]]; then
    echo "Git fetch failed after $max_attempts attempts." >&2
    exit 1
  fi

  echo "Git fetch attempt $attempt failed; retrying." >&2
  sleep $((attempt * 2))
done
