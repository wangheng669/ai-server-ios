#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
repo_url=$(git -C "$repo_root" remote get-url origin)
automation_root="$HOME/.local/share/ai-server-ios-actions-outage-fallback"
automation_repo="$automation_root/repo"
label=com.wangheng.ai-server-ios-actions-outage-fallback
launch_agents_dir="$HOME/Library/LaunchAgents"
plist_path="$launch_agents_dir/$label.plist"
log_dir="$HOME/Library/Logs/ai-server-ios"

mkdir -p "$launch_agents_dir" "$log_dir" "$automation_root"
if [[ ! -d "$automation_repo/.git" ]]; then
  git clone --branch main --single-branch "$repo_url" "$automation_repo"
else
  if [[ -n "$(git -C "$automation_repo" status --short)" ]]; then
    echo "Automation checkout is dirty: $automation_repo" >&2
    exit 1
  fi
  git -C "$automation_repo" fetch --no-tags origin main
  git -C "$automation_repo" switch main
  git -C "$automation_repo" merge --ff-only origin/main
fi
cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>cd '$automation_repo' &amp;&amp; ./ci/actions-outage-fallback-watch.sh</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log_dir/actions-outage-fallback.log</string>
  <key>StandardErrorPath</key><string>$log_dir/actions-outage-fallback.log</string>
</dict>
</plist>
EOF

plutil -lint "$plist_path"
launchctl bootout "gui/$(id -u)" "$plist_path" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist_path"
echo "Installed $label from $automation_repo."
