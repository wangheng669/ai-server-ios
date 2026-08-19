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
grep -Fq 'IOS_ACTIONS_OUTAGE_COMPLETED_LOOKBACK_SECONDS:-21600' <<<"$watch_source"
grep -Fq 'sort_by(.createdEpoch)' <<<"$watch_source"
grep -Fq 'group_by(.headBranch)' <<<"$watch_source"
grep -Fq 'any(. == "cancelled")' <<<"$watch_source"
grep -Fq 'all(. != "failure")' <<<"$watch_source"
grep -Fq 'git merge-base --is-ancestor "$run_sha" origin/main' <<<"$watch_source"
grep -Fq '/bin/bash ./ci/actions-outage-fallback-watch.sh' < ci/install-actions-outage-fallback-watch.sh
grep -Fq 'gh run cancel "$run_id"' <<<"$merge_source"
grep -Fq 'skips sources already merged into main' <<<"$merge_source"
grep -Fq 'repository_variable IOS_DEVICE_UDID' <<<"$merge_source"
grep -Fq 'report_local_delivery installed-local-fallback' <<<"$merge_source"
grep -Fq 'gh workflow run local-central-delivery-report.yml' <<<"$merge_source"

workflow_source=$(<.github/workflows/local-central-delivery-report.yml)
grep -Fq 'workflow_dispatch:' <<<"$workflow_source"
grep -Fq 'IOS_DEPLOYMENT_COMMIT:' <<<"$workflow_source"
grep -Fq 'report-ios-deployment.sh succeeded 1' <<<"$workflow_source"

echo "Actions outage fallback safety checks passed."
