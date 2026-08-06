#!/usr/bin/env bash

set -euo pipefail

for path in ci/local-central-merge.sh ci/actions-outage-fallback-watch.sh ci/install-actions-outage-fallback-watch.sh; do
  bash -n "$path"
done

watch_source=$(<ci/actions-outage-fallback-watch.sh)
merge_source=$(<ci/local-central-merge.sh)

grep -Fq 'partial_outage' <<<"$watch_source"
grep -Fq 'major_outage' <<<"$watch_source"
grep -Fq 'IOS_ACTIONS_OUTAGE_QUEUE_SECONDS:-300' <<<"$watch_source"
grep -Fq 'sort_by(.createdEpoch)' <<<"$watch_source"
grep -Fq 'gh run cancel "$run_id"' <<<"$merge_source"
grep -Fq 'refusing a duplicate local execution' <<<"$merge_source"

echo "Actions outage fallback safety checks passed."
