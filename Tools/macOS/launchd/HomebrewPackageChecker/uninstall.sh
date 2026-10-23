#!/bin/bash
# LaunchAgent の登録を解除して plist を削除する
set -eu
LABEL="com.masahiro.brew-check"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
echo "登録を解除しました"
