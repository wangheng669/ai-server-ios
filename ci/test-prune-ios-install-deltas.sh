#!/usr/bin/env bash
set -euo pipefail

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/ios-install-delta-prune-test.XXXXXX")
trap 'rm -rf "$sandbox"' EXIT
cache_root="$sandbox/AppInstallationBinaryDeltas"
bundle_id=com.example.app
bundle_cache="$cache_root/$bundle_id"
mkdir -p "$bundle_cache"

oldest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
older=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
newer=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
newest=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
for entry in "$oldest" "$older" "$newer" "$newest"; do
  mkdir "$bundle_cache/$entry"
done
mkdir "$bundle_cache/unexpected-entry"
touch -t 202601010101 "$bundle_cache/$oldest"
touch -t 202602010101 "$bundle_cache/$older"
touch -t 202603010101 "$bundle_cache/$newer"
touch -t 202604010101 "$bundle_cache/$newest"

preview=$(
  IOS_INSTALL_DELTA_CACHE_ROOT="$cache_root" \
    ./ci/prune-ios-install-deltas.sh --bundle-id "$bundle_id" --keep 2
)
grep -Fq 'Would prune 2 old installation delta(s)' <<<"$preview"
test -d "$bundle_cache/$oldest"
test -d "$bundle_cache/$older"

IOS_INSTALL_DELTA_CACHE_ROOT="$cache_root" \
  ./ci/prune-ios-install-deltas.sh --apply --bundle-id "$bundle_id" --keep 2
test ! -e "$bundle_cache/$oldest"
test ! -e "$bundle_cache/$older"
test -d "$bundle_cache/$newer"
test -d "$bundle_cache/$newest"
test -d "$bundle_cache/unexpected-entry"

if IOS_INSTALL_DELTA_CACHE_ROOT="$cache_root" \
  ./ci/prune-ios-install-deltas.sh --bundle-id '../unsafe' >/dev/null 2>&1; then
  echo 'Unsafe bundle identifiers must be rejected.' >&2
  exit 1
fi

echo 'iOS installation delta pruning checks passed.'
