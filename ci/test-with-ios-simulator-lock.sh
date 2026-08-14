#!/usr/bin/env bash
set -euo pipefail

script=./ci/with-ios-simulator-lock.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ai-server-ios-simulator-lock-test.XXXXXX")
lock_dir="$test_root/lock"
owner_pid=

cleanup() {
  if [[ -n "$owner_pid" ]]; then
    kill -TERM "$owner_pid" 2>/dev/null || true
    wait "$owner_pid" 2>/dev/null || true
  fi
  if [[ "$(basename "$test_root")" == ai-server-ios-simulator-lock-test.* ]]; then
    rm -rf "$test_root"
  fi
}
trap cleanup EXIT INT TERM

fail() {
  echo "$1" >&2
  exit 1
}

run_with_lock() {
  IOS_SIMULATOR_LOCK_DIR="$lock_dir" "$script" "$@"
}

output=$(run_with_lock --label smoke --wait-seconds 0 -- true)
grep -q 'Reserved iPhone 16e for smoke.' <<<"$output"
grep -q 'Released iPhone 16e simulator lock for smoke.' <<<"$output"
[[ ! -d "$lock_dir" ]] || fail 'Command lock was not released.'

IOS_SIMULATOR_LOCK_DIR="$lock_dir" "$script" \
  --label owner --wait-seconds 0 -- sleep 30 >"$test_root/owner.log" 2>&1 &
owner_pid=$!
for _ in {1..50}; do
  [[ -f "$lock_dir/owner" ]] && break
  kill -0 "$owner_pid" 2>/dev/null || fail 'Owner process exited before acquiring the lock.'
  sleep 0.1
done
[[ -f "$lock_dir/owner" ]] || fail 'Owner process did not acquire the lock.'

run_with_lock --label owner --assert-held >/dev/null
if run_with_lock --label another-task --assert-held >"$test_root/assert.log" 2>&1; then
  fail 'A different label unexpectedly passed --assert-held.'
fi
grep -q 'not by another-task' "$test_root/assert.log"

if run_with_lock --label contender --wait-seconds 0 -- true >"$test_root/wait.log" 2>&1; then
  fail 'A contender unexpectedly acquired an active lock.'
fi
grep -q 'Timed out waiting 0s for iPhone 16e' "$test_root/wait.log"

kill -TERM "$owner_pid"
wait "$owner_pid" 2>/dev/null || true
owner_pid=
[[ ! -d "$lock_dir" ]] || fail 'Interrupted command lock was not released.'

if run_with_lock --wait-seconds 1201 -- true >"$test_root/validation.log" 2>&1; then
  fail 'An out-of-range wait duration was accepted.'
fi
grep -q 'Wait duration must be between 0 and 1200 seconds.' "$test_root/validation.log"

grep -Fq '/[x]codebuild( [^ ]+)* (test|test-without-building)( |$)/ ||' "$script"
if grep -Fq '/[x]codebuild .*test/' "$script"; then
  fail 'build-for-testing would be mistaken for a running test.'
fi

help_output=$($script --help)
grep -q 'Commands wait up to 15 seconds by default' <<<"$help_output"
grep -q 'Interactive holds expire after 180 seconds by default' <<<"$help_output"

echo 'Simulator lock tests passed.'
