#!/usr/bin/env bash
# 退回旧方案（TG Pro + Hammerspoon 里的 tgpro-hotkey）。
# 用法：bash scripts/rollback-to-tgpro.sh <cutover-from-tgpro.sh 打印的备份目录>
# FanShift 的 App 和后台程序不会被删掉，只是退出并关掉自启；要彻底删除再跑 scripts/uninstall.sh。
set -euo pipefail

BACKUP="${1:-}"
[ -d "$BACKUP" ] || { echo "用法：bash scripts/rollback-to-tgpro.sh <备份目录>"; exit 1; }
TGPRO_DOMAIN="com.tunabellysoftware.tgpro"
NEW_AGENT_LABEL="com.kriswonka.fanshift.autostart"
OLD_AGENT_LABEL="com.kriswonka.tghotkey.autostart"

echo "== 退出 FanShift（退出时会把风扇交还系统）并关掉它的自启"
osascript -e 'quit app "FanShift"' >/dev/null 2>&1 || true
for _ in $(seq 1 10); do pgrep -x FanShift >/dev/null || break; sleep 0.3; done
launchctl bootout "gui/$(id -u)/${NEW_AGENT_LABEL}" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/${NEW_AGENT_LABEL}.plist"

echo "== 恢复 TG Pro 的设置和登录项"
if [ -f "$BACKUP/tgpro-prefs.plist" ]; then
    osascript -e 'quit app "TG Pro"' >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do pgrep -x "TG Pro" >/dev/null || break; sleep 0.5; done
    defaults import "$TGPRO_DOMAIN" "$BACKUP/tgpro-prefs.plist"
fi
if grep -q "tgpro-login-item" "$BACKUP/removed.txt" 2>/dev/null; then
    osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/TG Pro.app", hidden:true}' >/dev/null 2>&1 || true
fi

echo "== 恢复 Hammerspoon 的配置和旧的自启项"
if [ -f "$BACKUP/init.lua" ]; then
    cp "$BACKUP/init.lua" "$HOME/.hammerspoon/init.lua"
fi
if [ -f "$BACKUP/${OLD_AGENT_LABEL}.plist" ]; then
    cp "$BACKUP/${OLD_AGENT_LABEL}.plist" "$HOME/Library/LaunchAgents/"
fi
osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
for _ in $(seq 1 10); do pgrep -x Hammerspoon >/dev/null || break; sleep 0.3; done
pkill -x Hammerspoon 2>/dev/null || true
open -ga Hammerspoon
open -gja "/Applications/TG Pro.app"

echo "✅ 已退回旧方案：TG Pro 和 Hammerspoon 已重新启动，⌃⌥⌘8 由 Hammerspoon 接管。"
