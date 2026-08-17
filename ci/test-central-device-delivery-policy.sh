#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/ai-merge-to-main.yml
prepare=ci/prepare-central-runner-parallel.sh

grep -Fq 'IOS_REQUIRE_DEVICE_GATE:' "$workflow"
grep -Fq "steps.central_prepare.outputs.device_gate_failed != 'true'" "$workflow"
grep -Fq "steps.central_prepare.outputs.device_gate_failed == 'true' || steps.local_install.outcome == 'failure'" "$workflow"
grep -Fq 'published-pending-install' "$workflow"

if grep -Fq 'Fail delivery when local installation failed' "$workflow"; then
  echo 'Post-publish installation failure must not fail main delivery.' >&2
  exit 1
fi

grep -Fq 'if [[ "${IOS_REQUIRE_DEVICE_GATE:-false}" == true ]]' "$prepare"
grep -Fq 'main delivery will continue and installation will be retried after publish' "$prepare"

echo 'Central device delivery policy checks passed.'
