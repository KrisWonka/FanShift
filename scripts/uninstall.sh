#!/usr/bin/env bash
# 卸载 FanShift：退出 App、把风扇交还系统、删掉后台程序和 App。配置文件留着，想删见最后的提示。
set -uo pipefail

APP_NAME="FanShift"
DAEMON_LABEL="com.kriswonka.fanshift.daemon"
AUTOSTART_LABEL="com.kriswonka.fanshift.autostart"

osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1
sleep 1

launchctl bootout "gui/$(id -u)/${AUTOSTART_LABEL}" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/${AUTOSTART_LABEL}.plist"

if [ -f "/Library/LaunchDaemons/${DAEMON_LABEL}.plist" ] || [ -f "/Library/PrivilegedHelperTools/${DAEMON_LABEL}" ]; then
    echo "→ 删除后台程序（需要管理员密码）"
    # 后台程序收到退出信号时会先把风扇交还系统
    sudo sh -c "launchctl bootout system/${DAEMON_LABEL} 2>/dev/null; rm -f /Library/LaunchDaemons/${DAEMON_LABEL}.plist /Library/PrivilegedHelperTools/${DAEMON_LABEL} /var/run/${DAEMON_LABEL}.holding"
fi

rm -rf "/Applications/${APP_NAME}.app"
echo "✅ 已卸载。配置还留在 ~/Library/Application Support/${APP_NAME}/，不需要的话手动删掉。"
