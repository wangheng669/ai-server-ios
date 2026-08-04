#!/bin/bash

set -euo pipefail

lock_dir=${IOS_SIMULATOR_LOCK_DIR:-/tmp/ai-server-ios-iphone16e.lock}
wait_seconds=${IOS_SIMULATOR_LOCK_WAIT_SECONDS:-1200}
hold_seconds=${IOS_SIMULATOR_LOCK_HOLD_SECONDS:-600}
label=${IOS_SIMULATOR_LOCK_LABEL:-$(basename "$PWD")}
hold=false
show_status=false
assert_held=false

usage() {
  cat <<'EOF'
Usage:
  with-ios-simulator-lock.sh [--label NAME] -- COMMAND [ARG ...]
  with-ios-simulator-lock.sh [--label NAME] [--hold-seconds SECONDS] --hold
  with-ios-simulator-lock.sh [--label NAME] --assert-held
  with-ios-simulator-lock.sh --status

Use --hold to reserve the shared iPhone 16e during interactive UI checks.
Interactive holds expire after 600 seconds by default. Stop the holding
process as soon as verification is complete to release the lock earlier.
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
    --hold-seconds)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      hold_seconds=$2
      shift 2
      ;;
    --status)
      show_status=true
      shift
      ;;
    --assert-held)
      assert_held=true
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

if ! [[ "$hold_seconds" =~ ^[0-9]+$ ]] || (( hold_seconds < 30 || hold_seconds > 900 )); then
  echo "Hold duration must be between 30 and 900 seconds." >&2
  exit 2
fi

owner_file="$lock_dir/owner"
host_name=$(hostname)

find_unmanaged_automation() {
  local candidate_pid parent_info parent_pid parent_command managed
  while read -r candidate_pid; do
    [[ -n "$candidate_pid" && "$candidate_pid" != "$$" ]] || continue
    parent_pid=$candidate_pid
    managed=false
    while [[ "$parent_pid" =~ ^[0-9]+$ ]] && (( parent_pid > 1 )); do
      parent_info=$(ps -p "$parent_pid" -o ppid=,command= 2>/dev/null || true)
      [[ -n "$parent_info" ]] || break
      read -r parent_pid parent_command <<< "$parent_info"
      if [[ "$parent_command" == *"with-ios-simulator-lock.sh"* ]]; then
        managed=true
        break
      fi
    done
    if [[ "$managed" == false ]]; then
      ps -p "$candidate_pid" -o pid=,command= 2>/dev/null || true
    fi
  done < <(ps ax -o pid=,command= | awk -v self="$$" '
    $1 == self { next }
    /[w]ith-ios-simulator-lock\.sh/ { next }
    /[x]codebuild .*test/ ||
    /[m]aestro .*test/ ||
    /[i]db (ui|xctest|record|launch)/ ||
    /[f]b-idb .* (ui|xctest|record|launch)/ ||
    /[s]imctl (io|ui) / ||
    /[a]ppium/ ||
    /[W]ebDriverAgentRunner/ ||
    /[x]ctest .*Runner/ { print $1 }
  ')
}

read_owner_field() {
  local field=$1
  [[ -f "$owner_file" ]] || return 0
  awk -F= -v field="$field" '$1 == field {sub(/^[^=]*=/, ""); print; exit}' "$owner_file"
}

describe_owner() {
  local owner_label owner_pid owner_started owner_cwd owner_mode owner_expires
  owner_label=$(read_owner_field label)
  owner_pid=$(read_owner_field pid)
  owner_started=$(read_owner_field started)
  owner_cwd=$(read_owner_field cwd)
  owner_mode=$(read_owner_field mode)
  owner_expires=$(read_owner_field expires)
  echo "${owner_label:-unknown task} (pid ${owner_pid:-unknown}, mode ${owner_mode:-unknown}, since ${owner_started:-unknown}, expires ${owner_expires:-not set}, cwd ${owner_cwd:-unknown})"
}

if [[ "$assert_held" == true ]]; then
  [[ "$show_status" == false && "$hold" == false && $# -eq 0 ]] || {
    echo "--assert-held cannot be combined with another action or command." >&2
    exit 2
  }
  if [[ ! -d "$lock_dir" ]]; then
    echo "iPhone 16e simulator lock is not held." >&2
    exit 1
  fi
  owner_label=$(read_owner_field label)
  if [[ -n "$label" && "$owner_label" != "$label" ]]; then
    echo "iPhone 16e is held by $(describe_owner), not by $label." >&2
    exit 1
  fi
  echo "iPhone 16e lock is held by $(describe_owner)."
  exit 0
fi

if [[ "$show_status" == true ]]; then
  if [[ -d "$lock_dir" ]]; then
    echo "iPhone 16e is reserved by $(describe_owner)."
    exit 0
  fi
  unmanaged=$(find_unmanaged_automation)
  if [[ -n "$unmanaged" ]]; then
    echo "iPhone 16e has unmanaged automation processes (no repository lock):"
    echo "$unmanaged"
    exit 1
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
      if [[ "$hold" == true ]]; then
        echo "mode=interactive-hold"
        echo "expires=$(date -u -r $(( $(date +%s) + hold_seconds )) +%Y-%m-%dT%H:%M:%SZ)"
      else
        echo "mode=command"
        echo "expires="
      fi
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

unmanaged=$(find_unmanaged_automation)
if [[ -n "$unmanaged" ]]; then
  echo "Refusing to start while unmanaged simulator automation is active:" >&2
  echo "$unmanaged" >&2
  echo "Stop it, or restart it through ci/with-ios-simulator-lock.sh." >&2
  exit 1
fi

echo "Reserved iPhone 16e for $label."

if [[ "$hold" == true ]]; then
  echo "Interactive hold is active for at most ${hold_seconds}s; stop this process after UI verification."
  sleep "$hold_seconds" &
  child_pid=$!
  wait "$child_pid"
  child_pid=""
  echo "Interactive hold for $label reached its ${hold_seconds}s limit."
  exit 0
fi

set +e
"$@" &
child_pid=$!
wait "$child_pid"
command_status=$?
child_pid=""
set -e
exit "$command_status"
