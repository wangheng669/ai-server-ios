#!/bin/bash

set -euo pipefail

repo_dir="${1:-$(git rev-parse --show-toplevel)}"
exec "$repo_dir/ci/automatic-main-sync.sh" "$repo_dir"
