#!/bin/bash

set -euo pipefail

repo_dir="$(git rev-parse --show-toplevel)"
label="com.wangheng.ai-server-ios.testflight-upload"
launch_agents_dir="$HOME/Library/LaunchAgents"
plist_path="$launch_agents_dir/$label.plist"
log_dir="$HOME/Library/Logs/ai-server-ios"
support_dir="$HOME/Library/Application Support/ai-server-ios"
installed_script="$support_dir/trigger-local-testflight.sh"

mkdir -p "$launch_agents_dir" "$log_dir" "$support_dir"
install -m 755 "$repo_dir/ci/trigger-local-testflight.sh" "$installed_script"

escaped_home_dir="$(printf '%s' "$HOME" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')"
escaped_installed_script="$(printf '%s' "$installed_script" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')"

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
    <string>$escaped_installed_script</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$escaped_home_dir</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>4</integer>
    <key>Minute</key>
    <integer>30</integer>
  </dict>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$log_dir/testflight-upload.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/testflight-upload.error.log</string>
</dict>
</plist>
EOF

plutil -lint "$plist_path"
launchctl bootout "gui/$(id -u)" "$plist_path" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist_path"

echo "Installed $label. It will trigger TestFlight every day at 04:30 local time."
