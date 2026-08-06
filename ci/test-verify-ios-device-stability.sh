#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ios-device-stability-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"

cat > "$test_root/bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"info details"* ]]; then
  output=''
  while (($#)); do
    if [[ "$1" == --json-output ]]; then output=$2; break; fi
    shift
  done
  printf '{"result":{"deviceProperties":{"name":"Test iPhone"}}}' > "$output"
  exit 0
fi
[[ "${MOCK_PROCESS_READY:-true}" == true ]]
SH
cat > "$test_root/bin/ioreg" <<'SH'
#!/usr/bin/env bash
[[ "${MOCK_USB_READY:-true}" == true ]] && echo 'USB Serial Number 00008110-TEST'
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
  PATH="$test_root/bin:$PATH" DEVICE_UDID=00008110-TEST \
    IOS_DEVICE_STABILITY_ATTEMPTS=3 IOS_DEVICE_STABILITY_INTERVAL_SECONDS=0 \
    "$repo_root/ci/verify-ios-device-stability.sh"
}

output=$(run_gate)
grep -Fq '连续 3 次检测正常' <<< "$output"

if MOCK_USB_READY=false run_gate >/dev/null 2>&1; then
  echo 'The gate must reject a device without USB.' >&2
  exit 1
fi
if MOCK_PROCESS_READY=false run_gate >/dev/null 2>&1; then
  echo 'The gate must reject a locked or unusable device.' >&2
  exit 1
fi
if MOCK_XCODE_READY=false run_gate >/dev/null 2>&1; then
  echo 'The gate must reject a device unavailable to Xcode.' >&2
  exit 1
fi

echo 'iOS device stability gate tests passed.'
