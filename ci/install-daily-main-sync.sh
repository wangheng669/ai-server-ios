#!/bin/bash

set -euo pipefail

repo_dir="$(git rev-parse --show-toplevel)"
label="com.wangheng.ai-server-ios.daily-main-sync"
launch_agents_dir="$HOME/Library/LaunchAgents"
plist_path="$launch_agents_dir/$label.plist"
log_dir="$HOME/Library/Logs/ai-server-ios"
mkdir -p "$launch_agents_dir" "$log_dir"

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
    <string>/bin/bash</string>
    <string>$escaped_repo_dir/ci/daily-main-sync.sh</string>
    <string>$escaped_repo_dir</string>
  </array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>https_proxy</key><string>http://127.0.0.1:7890</string>
    <key>http_proxy</key><string>http://127.0.0.1:7890</string>
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

echo "Installed $label. It will run every 5 minutes while logged in."
