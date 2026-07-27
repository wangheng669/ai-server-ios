#!/bin/bash

set -euo pipefail

repo_dir="$(git rev-parse --show-toplevel)"
label="com.wangheng.ai-server-ios.daily-main-sync"
launch_agents_dir="$HOME/Library/LaunchAgents"
plist_path="$launch_agents_dir/$label.plist"
log_dir="$HOME/Library/Logs/ai-server-ios"
support_dir="$HOME/Library/Application Support/ai-server-ios"
runner_path="$support_dir/run-daily-main-sync.applescript"

mkdir -p "$launch_agents_dir" "$log_dir" "$support_dir"

cp "$repo_dir/ci/run-daily-main-sync.applescript" "$runner_path"

escaped_repo_dir="$(printf '%s' "$repo_dir" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')"

cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/osascript</string>
    <string>$runner_path</string>
    <string>$escaped_repo_dir/ci/daily-main-sync.sh</string>
    <string>$escaped_repo_dir</string>
    <string>$log_dir/daily-main-sync.log</string>
    <string>$log_dir/daily-main-sync.error.log</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>3</integer>
    <key>Minute</key>
    <integer>10</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$log_dir/daily-main-sync.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/daily-main-sync.error.log</string>
</dict>
</plist>
EOF

plutil -lint "$plist_path"
launchctl bootout "gui/$(id -u)" "$plist_path" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist_path"

echo "Installed $label. It will run every day at 03:10 local time."
