#!/bin/bash

set -euo pipefail

lock_dir=${IOS_SIMULATOR_LOCK_DIR:-/tmp/ai-server-ios-iphone16e.lock}
wait_seconds=${IOS_SIMULATOR_LOCK_WAIT_SECONDS:-1200}
label=${IOS_SIMULATOR_LOCK_LABEL:-$(basename "$PWD")}
hold=false
show_status=false

usage() {
  cat <<'EOF'
Usage:
  with-ios-simulator-lock.sh [--label NAME] -- COMMAND [ARG ...]
  with-ios-simulator-lock.sh [--label NAME] --hold
  with-ios-simulator-lock.sh --status

Use --hold to reserve the shared iPhone 16e during interactive UI checks.
Stop the holding process when verification is complete to release the lock.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      label=$2
      shift 2
      ;;
    --hold)
      hold=true
      shift
      ;;
    --status)
      show_status=true
      shift
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$lock_dir" != /* || "$lock_dir" == "/" ]]; then
  echo "IOS_SIMULATOR_LOCK_DIR must be a specific absolute path." >&2
  exit 2
fi

owner_file="$lock_dir/owner"
host_name=$(hostname)

read_owner_field() {
  local field=$1
  [[ -f "$owner_file" ]] || return 0
  awk -F= -v field="$field" '$1 == field {sub(/^[^=]*=/, ""); print; exit}' "$owner_file"
}

describe_owner() {
  local owner_label owner_pid owner_started owner_cwd
  owner_label=$(read_owner_field label)
  owner_pid=$(read_owner_field pid)
  owner_started=$(read_owner_field started)
  owner_cwd=$(read_owner_field cwd)
  echo "${owner_label:-unknown task} (pid ${owner_pid:-unknown}, since ${owner_started:-unknown}, cwd ${owner_cwd:-unknown})"
}

if [[ "$show_status" == true ]]; then
  if [[ -d "$lock_dir" ]]; then
    echo "iPhone 16e is reserved by $(describe_owner)."
    exit 0
  fi
  echo "iPhone 16e is available."
  exit 0
fi

if [[ "$hold" == false && $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

if [[ "$hold" == true && $# -gt 0 ]]; then
  echo "--hold cannot be combined with a command." >&2
  exit 2
fi

acquired=false
child_pid=""

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
release_lock() {
  if [[ "$acquired" != true || ! -d "$lock_dir" ]]; then
    return
  fi

  local owner_pid
  owner_pid=$(read_owner_field pid)
  if [[ "$owner_pid" == "$$" ]]; then
    rm -f "$owner_file"
    rmdir "$lock_dir" 2>/dev/null || true
    echo "Released iPhone 16e simulator lock for $label."
  fi
}

# shellcheck disable=SC2329 # Invoked by the signal traps.
stop_and_release() {
  if [[ -n "$child_pid" ]]; then
    kill "$child_pid" 2>/dev/null || true
  fi
  exit 130
}

trap release_lock EXIT
trap stop_and_release INT TERM HUP

deadline=$(( $(date +%s) + wait_seconds ))
last_report=0

while [[ "$acquired" != true ]]; do
  if mkdir "$lock_dir" 2>/dev/null; then
    {
      echo "pid=$$"
      echo "host=$host_name"
      echo "label=$label"
      echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "cwd=$PWD"
    } > "$owner_file"
    acquired=true
    break
  fi

  owner_pid=$(read_owner_field pid)
  owner_host=$(read_owner_field host)
  if [[ "$owner_host" == "$host_name" && "$owner_pid" =~ ^[0-9]+$ ]] \
    && ! kill -0 "$owner_pid" 2>/dev/null; then
    stale_dir="${lock_dir}.stale.$$"
    if mv "$lock_dir" "$stale_dir" 2>/dev/null; then
      rm -f "$stale_dir/owner"
      rmdir "$stale_dir" 2>/dev/null || true
      echo "Removed stale iPhone 16e simulator lock from pid $owner_pid."
      continue
    fi
  fi

  now=$(date +%s)
  if (( now >= deadline )); then
    echo "Timed out waiting ${wait_seconds}s for iPhone 16e; held by $(describe_owner)." >&2
    exit 1
  fi
  if (( now - last_report >= 15 )); then
    echo "Waiting for iPhone 16e; currently held by $(describe_owner)."
    last_report=$now
  fi
  sleep 2
done

echo "Reserved iPhone 16e for $label."

if [[ "$hold" == true ]]; then
  echo "Interactive hold is active; stop this process after UI verification."
  while true; do
    sleep 30
  done
fi

set +e
"$@" &
child_pid=$!
wait "$child_pid"
command_status=$?
child_pid=""
set -e
exit "$command_status"
