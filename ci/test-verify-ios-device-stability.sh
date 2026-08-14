#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ios-device-stability-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"

cat > "$test_root/bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"device info details"* ]]; then
  output=''
  while (($#)); do
    if [[ "$1" == --json-output ]]; then output=$2; break; fi
    shift
  done
  printf '{"result":{"deviceProperties":{"name":"Test iPhone"},"hardwareProperties":{"udid":"00008110-TEST"}}}' > "$output"
  exit 0
fi
if [[ "$*" == *"device info processes"* ]]; then
  if [[ -n "${MOCK_PROCESS_COUNTER_FILE:-}" ]]; then
    count=0
    [[ ! -f "$MOCK_PROCESS_COUNTER_FILE" ]] || count=$(cat "$MOCK_PROCESS_COUNTER_FILE")
    count=$((count + 1))
    printf '%s\n' "$count" > "$MOCK_PROCESS_COUNTER_FILE"
    if ((count <= ${MOCK_PROCESS_FAILURES_BEFORE_READY:-0})); then
      echo 'CoreDevice service is still starting' >&2
      exit 1
    fi
  fi
  [[ "${MOCK_PROCESS_READY:-true}" == true ]]
  exit
fi
echo "Unexpected xcrun command: $*" >&2
exit 64
SH
cat > "$test_root/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
[[ "${MOCK_XCODE_READY:-true}" == true ]] && echo 'platform:iOS, id:00008110-TEST, name:Test iPhone'
SH
cat > "$test_root/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$test_root/bin/"*

run_gate() {
  PATH="$test_root/bin:$PATH" DEVICE_UDID=COREDEVICE-TEST \
    IOS_DEVICE_STABILITY_ATTEMPTS=3 IOS_DEVICE_STABILITY_INTERVAL_SECONDS=0 \
    IOS_DEVICE_STABILITY_MAX_ATTEMPTS="${IOS_DEVICE_STABILITY_MAX_ATTEMPTS:-6}" \
    "$repo_root/ci/verify-ios-device-stability.sh"
}

output=$(run_gate)
grep -Fq '连续 3 次检测正常' <<< "$output"

process_counter="$test_root/process-counter"
output=$(MOCK_PROCESS_COUNTER_FILE="$process_counter" \
  MOCK_PROCESS_FAILURES_BEFORE_READY=2 run_gate 2>&1)
grep -Fq '总探测 5/6' <<< "$output"
grep -Fq '连续 3 次检测正常' <<< "$output"

if IOS_DEVICE_STABILITY_MAX_ATTEMPTS=4 MOCK_PROCESS_READY=false run_gate >/dev/null 2>&1; then
  echo 'The gate must reject a locked or unusable device.' >&2
  exit 1
fi
if IOS_DEVICE_STABILITY_MAX_ATTEMPTS=4 MOCK_XCODE_READY=false run_gate >/dev/null 2>&1; then
  echo 'The gate must reject a device unavailable to Xcode.' >&2
  exit 1
fi

echo 'iOS device stability gate tests passed.'
