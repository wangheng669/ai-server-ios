#!/usr/bin/env bash
set -euo pipefail

apply=false
bundle_id=${BUNDLE_ID:-com.wangheng.aiserverclient}
keep_count=${IOS_INSTALL_DELTA_CACHE_KEEP:-3}
cache_root=${IOS_INSTALL_DELTA_CACHE_ROOT:-"$HOME/Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas"}

usage() {
  cat <<'EOF'
Usage: prune-ios-install-deltas.sh [--apply] [--bundle-id ID] [--keep COUNT]

Keeps the newest installation deltas for one app bundle. The default is a
read-only preview; pass --apply to remove older deltas.
EOF
}

while (($#)); do
  case "$1" in
    --apply)
      apply=true
      shift
      ;;
    --bundle-id)
      bundle_id=${2:?--bundle-id requires a value}
      shift 2
      ;;
    --keep)
      keep_count=${2:?--keep requires a value}
      shift 2
      ;;
    -h | --help)
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

if [[ ! "$keep_count" =~ ^[0-9]+$ ]] || ((keep_count < 1 || keep_count > 50)); then
  echo "--keep must be an integer between 1 and 50." >&2
  exit 2
fi
if [[ ! "$bundle_id" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*$ ]]; then
  echo "Invalid bundle identifier: $bundle_id" >&2
  exit 2
fi

bundle_cache="$cache_root/$bundle_id"
if [[ ! -d "$bundle_cache" ]]; then
  echo "No installation delta cache exists for $bundle_id."
  exit 0
fi

entry_mtime() {
  stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1"
}

records=()
while IFS= read -r -d '' entry; do
  name=${entry##*/}
  if [[ ! "$name" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Skipping unexpected cache entry: $entry" >&2
    continue
  fi
  records+=("$(entry_mtime "$entry") $name")
done < <(find "$bundle_cache" -mindepth 1 -maxdepth 1 -type d -print0)

if ((${#records[@]} <= keep_count)); then
  echo "Installation delta cache already has ${#records[@]} item(s); keeping up to $keep_count."
  exit 0
fi

sorted_records=$(printf '%s\n' "${records[@]}" | sort -nr)
pruned=0
while read -r _ name; do
  [[ -n "$name" ]] || continue
  if ((pruned + keep_count < ${#records[@]})); then
    entry="$bundle_cache/$name"
    if [[ "$apply" == true ]]; then
      rm -rf "$entry"
    else
      echo "Would remove $entry"
    fi
    pruned=$((pruned + 1))
  fi
done < <(printf '%s\n' "$sorted_records" | sort -n)

if [[ "$apply" == true ]]; then
  echo "Pruned $pruned old installation delta(s); kept the newest $keep_count for $bundle_id."
else
  echo "Would prune $pruned old installation delta(s); the newest $keep_count would remain for $bundle_id."
fi
