#!/bin/bash
# LaunchAgent を生成・登録する（毎週月曜 9:00 実行）
set -eu
LABEL="com.masahiro.brew-check"
DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

chmod +x "$DIR/brew-check.sh"
mkdir -p "$HOME/Library/LaunchAgents" "$DIR/logs" "$DIR/reports"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$DIR/brew-check.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>1</integer>
    <key>Hour</key><integer>9</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>$DIR/logs/brew-check.log</string>
  <key>StandardErrorPath</key><string>$DIR/logs/brew-check.err.log</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
PLIST

plutil -lint "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "登録しました: $PLIST"
echo "今すぐテスト実行: launchctl kickstart gui/$(id -u)/$LABEL"
