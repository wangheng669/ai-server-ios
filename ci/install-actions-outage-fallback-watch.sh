#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
label=com.wangheng.ai-server-ios-actions-outage-fallback
launch_agents_dir="$HOME/Library/LaunchAgents"
plist_path="$launch_agents_dir/$label.plist"
log_dir="$HOME/Library/Logs/ai-server-ios"

mkdir -p "$launch_agents_dir" "$log_dir"
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
    <string>cd '$repo_root' &amp;&amp; ./ci/actions-outage-fallback-watch.sh</string>
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
echo "Installed $label from $repo_root."
