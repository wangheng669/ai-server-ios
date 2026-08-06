#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./ci/local-central-merge.sh \
    --source codex/task-branch \
    --failed-run GITHUB_RUN_ID \
    --confirm-infrastructure-failure

Emergency central-Mac fallback for a GitHub Actions infrastructure outage.
The source branch must be pushed, and the matching Actions run must be failed.
EOF
}

source_branch=""
failed_run_id=""
confirmed=false
while (($#)); do
  case "$1" in
    --source)
      source_branch=${2:-}
      shift 2
      ;;
    --failed-run)
      failed_run_id=${2:-}
      shift 2
      ;;
    --confirm-infrastructure-failure)
      confirmed=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$source_branch" =~ ^codex/[A-Za-z0-9._/-]+$ ]]; then
  echo "--source must name a pushed codex/* task branch." >&2
  exit 2
fi
if [[ ! "$failed_run_id" =~ ^[0-9]+$ ]]; then
  echo "--failed-run must be a numeric GitHub Actions run id." >&2
  exit 2
fi
if [[ "$confirmed" != true ]]; then
  echo "Explicit --confirm-infrastructure-failure is required." >&2
  exit 2
fi

for command in git gh xcodebuild xcrun jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is unavailable: $command" >&2
    exit 1
  fi
done

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
if [[ -n "$(git status --short)" ]]; then
  echo "The invoking worktree must be clean." >&2
  exit 1
fi

run_json=$(gh run view "$failed_run_id" --json conclusion,headBranch,headSha,url)
run_conclusion=$(jq -r .conclusion <<<"$run_json")
run_branch=$(jq -r .headBranch <<<"$run_json")
run_sha=$(jq -r .headSha <<<"$run_json")
run_url=$(jq -r .url <<<"$run_json")
if [[ "$run_conclusion" != failure || "$run_branch" != "$source_branch" ]]; then
  echo "Run $failed_run_id is not a failed run for $source_branch." >&2
  exit 1
fi
echo "Validated failed Actions run: $run_url"

git config http.version HTTP/1.1
git fetch --no-tags origin \
  main:refs/remotes/origin/main \
  "$source_branch:refs/remotes/origin/$source_branch"
source_sha=$(git rev-parse "origin/$source_branch")
if [[ "$source_sha" != "$run_sha" ]]; then
  echo "The task branch changed after failed run $failed_run_id; refusing stale approval." >&2
  exit 1
fi
if git merge-base --is-ancestor "$source_sha" origin/main; then
  echo "$source_branch is already present in origin/main."
  exit 0
fi

lock_dir=/tmp/ai-server-ios-local-central-merge.lock
if ! mkdir "$lock_dir" 2>/dev/null; then
  owner=$(cat "$lock_dir/pid" 2>/dev/null || true)
  echo "Another local central merge is active${owner:+ (pid $owner)}." >&2
  exit 1
fi
printf '%s\n' "$$" > "$lock_dir/pid"

worktree_root=$(mktemp -d /tmp/ai-server-ios-central.XXXXXX)
worktree_path="$worktree_root/repo"
cleanup_worktree=true
cleanup() {
  if [[ "$cleanup_worktree" == true ]]; then
    git -C "$repo_root" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
    rmdir "$worktree_root" >/dev/null 2>&1 || true
  fi
  rm -f "$lock_dir/pid"
  rmdir "$lock_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

git worktree add --detach "$worktree_path" origin/main
cd "$worktree_path"
git config user.name "Local Central Merge Bot"
git config user.email "actions@users.noreply.github.com"

if ! git merge --no-ff --no-commit "$source_sha"; then
  cleanup_worktree=false
  echo "Merge conflicts require semantic resolution. Preserved worktree: $worktree_path" >&2
  exit 1
fi
git commit -m "Merge $source_branch into main"

IOS_PREFLIGHT_SKIP_FETCH=true ./ci/linux-preflight.sh origin/main
scope=$(./ci/classify-ios-test-scope.sh < <(git diff --name-only origin/main...HEAD))
app_changed=$(awk -F= '$1 == "app_changed" { print $2 }' <<<"$scope")

if [[ "$app_changed" == true ]]; then
  export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
  export RUNNER_TEMP=${RUNNER_TEMP:-$(mktemp -d /tmp/ai-server-ios-runner.XXXXXX)}
  export IOS_BUILD_CACHE_ROOT=${IOS_BUILD_CACHE_ROOT:-$HOME/Library/Caches/ai-server-ios}
  export DEVICE_UDID=${DEVICE_UDID:-$(gh variable get IOS_DEVICE_UDID)}
  export TEAM_ID=${TEAM_ID:-$(gh variable get IOS_TEAM_ID)}
  export BUNDLE_ID=${BUNDLE_ID:-$(gh variable get IOS_BUNDLE_ID)}

  ./ci/verify-ios-device-stability.sh
  mkdir -p "$IOS_BUILD_CACHE_ROOT" "$RUNNER_TEMP"
  ./ci/with-ios-simulator-lock.sh \
    --label "local central merge $failed_run_id" \
    -- xcodebuild test \
      -project AIServerClient.xcodeproj \
      -scheme AIServerClient \
      -destination 'platform=iOS Simulator,name=iPhone 16e' \
      -collect-test-diagnostics never \
      -derivedDataPath "$IOS_BUILD_CACHE_ROOT/local-central-simulator" \
      -clonedSourcePackagesDirPath "$IOS_BUILD_CACHE_ROOT/source-packages" \
      CODE_SIGNING_ALLOWED=NO

  signing_path="$IOS_BUILD_CACHE_ROOT/local-central-signing"
  xcodebuild build \
    -project AIServerClient.xcodeproj \
    -scheme AIServerClient \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$signing_path" \
    -clonedSourcePackagesDirPath "$IOS_BUILD_CACHE_ROOT/source-packages" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic
  app_path="$signing_path/Build/Products/Debug-iphoneos/AIServerClient.app"
  test -d "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
  export APP_ARCHIVE="$RUNNER_TEMP/AIServerClient.app.zip"
  export APP_PATH="$RUNNER_TEMP/signed-app/AIServerClient.app"
  export IOS_SIGNING_DERIVED_DATA_PATH="$signing_path"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$APP_ARCHIVE"
fi

# Recheck immediately before publication so a concurrent main update cannot be lost.
git fetch --no-tags origin main:refs/remotes/origin/main
if [[ "$(git rev-parse HEAD^1)" != "$(git rev-parse origin/main)" ]]; then
  echo "origin/main changed during verification; refusing to publish. Rerun from the new main." >&2
  exit 1
fi
git push origin HEAD:main
git fetch --no-tags origin main:refs/remotes/origin/main
git merge-base --is-ancestor "$source_sha" origin/main

if [[ "$app_changed" == true ]]; then
  ./ci/sign-and-install-ios.sh
fi

echo "Local central fallback completed: $source_sha is in origin/main."
