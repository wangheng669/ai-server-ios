#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  DEVICE_UDID=... TEAM_ID=... BUNDLE_ID=... \
    ./ci/install-published-main-locally.sh \
      --source-sha SHA --source-branch codex/task --failed-run RUN_ID

Installs an already-merged stable main build after a central installation
infrastructure failure, then reports the accepted local fallback delivery.
EOF
}

source_sha=""
source_branch=""
run_id=""
while (($#)); do
  case "$1" in
    --source-sha) source_sha=${2:-}; shift 2 ;;
    --source-branch) source_branch=${2:-}; shift 2 ;;
    --failed-run) run_id=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

: "${DEVICE_UDID:?DEVICE_UDID is required}"
: "${TEAM_ID:?TEAM_ID is required}"
: "${BUNDLE_ID:?BUNDLE_ID is required}"
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "--source-sha must be a full commit SHA." >&2; exit 2; }
[[ "$source_branch" =~ ^codex/[A-Za-z0-9._/-]+$ ]] || { echo "--source-branch must be codex/*." >&2; exit 2; }
[[ "$run_id" =~ ^[0-9]+$ ]] || { echo "--failed-run must be numeric." >&2; exit 2; }

for command in codesign curl ditto git jq xcodebuild xcrun; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command is unavailable: $command" >&2; exit 1; }
done
if [[ -z "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
  command -v gh >/dev/null 2>&1 || { echo "gh or DEPLOYMENT_STATUS_API_KEY is required for governance reporting." >&2; exit 1; }
  gh auth status >/dev/null
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
[[ "$(git branch --show-current)" == main ]] || { echo "Formal local installation must run from the stable main workspace." >&2; exit 1; }
[[ -z "$(git status --short)" ]] || { echo "The stable main workspace must be clean." >&2; exit 1; }
git fetch --no-tags origin main:refs/remotes/origin/main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "Local main is not the latest origin/main." >&2; exit 1; }
git merge-base --is-ancestor "$source_sha" origin/main || { echo "$source_sha is not in origin/main." >&2; exit 1; }

operations_url=${IOS_DELIVERY_OPERATIONS_URL:-https://api.wanghengai.xin/api/admin/v1/system/ios-delivery-operations}
authorization=$(curl --fail --silent --show-error --max-time 15 "$operations_url")
if [[ "$(jq -r '.data.localCentralAuthorization.enabled // false' <<<"$authorization")" != true ]]; then
  echo "治理后台未授权本地中央兜底。" >&2
  exit 1
fi

export IOS_DEVICE_READY_JSON
IOS_DEVICE_READY_JSON=$(mktemp "${RUNNER_TEMP:-/tmp}/ios-local-install-device.XXXXXX")
trap 'rm -f "$IOS_DEVICE_READY_JSON"' EXIT
./ci/verify-ios-device-stability.sh
export IOS_DEVICE_ID IOS_DEVICE_NAME
IOS_DEVICE_ID=$(jq -r '.deviceId' "$IOS_DEVICE_READY_JSON")
IOS_DEVICE_NAME=$(jq -r '.deviceName' "$IOS_DEVICE_READY_JSON")

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
cache_root=${IOS_BUILD_CACHE_ROOT:-$HOME/Library/Caches/ai-server-ios}
signing_path="$cache_root/published-main-signing"
package_root=$(mktemp -d "${RUNNER_TEMP:-/tmp}/ios-published-main.XXXXXX")
cleanup_package() { rm -rf "$package_root"; }
trap 'rm -f "$IOS_DEVICE_READY_JSON"; cleanup_package' EXIT
mkdir -p "$cache_root"

xcodebuild build \
  -project AIServerClient.xcodeproj \
  -scheme AIServerClient \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$signing_path" \
  -clonedSourcePackagesDirPath "$cache_root/source-packages" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  COMPILER_INDEX_STORE_ENABLE=NO

app_path="$signing_path/Build/Products/Debug-iphoneos/AIServerClient.app"
test -d "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

export APP_ARCHIVE="$package_root/AIServerClient.app.zip"
export APP_PATH="$package_root/signed-app/AIServerClient.app"
export IOS_SIGNING_DERIVED_DATA_PATH="$signing_path"
export IOS_DELIVERY_MODE=local-fallback
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$APP_ARCHIVE"
./ci/sign-and-install-ios.sh

export IOS_DEPLOYMENT_COMMIT="$source_sha"
export IOS_DEPLOYMENT_SOURCE_BRANCH="$source_branch"
export IOS_DEPLOYMENT_RUN_ID="$run_id"
if [[ -n "${DEPLOYMENT_STATUS_API_KEY:-}" ]]; then
  ./ci/report-ios-deployment.sh succeeded 1 installed-local-fallback
else
  gh workflow run local-central-delivery-report.yml \
    --ref main \
    -f source_sha="$source_sha" \
    -f source_branch="$source_branch" \
    -f originating_run_id="$run_id" \
    -f stage=installed-local-fallback \
    -f device_id="$IOS_DEVICE_ID" \
    -f device_name="$IOS_DEVICE_NAME"
fi

echo "已从稳定 main 安装 $BUNDLE_ID 到 ${IOS_DEVICE_NAME:-$IOS_DEVICE_ID}，并完成治理回写。"
