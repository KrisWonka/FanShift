#!/usr/bin/env bash
# 从旧方案（TG Pro + Hammerspoon 里的 tgpro-hotkey）切换到 FanShift。只需要跑一次。
#
# 做的事（每一步改之前都先备份，备份目录最后会打印出来）：
#   1. 编译并把 FanShift 装进 /Applications
#   2. 退出 TG Pro，并把它的风扇控制改回「系统默认」
#      （这样以后再打开 TG Pro 看传感器，它也不会和 FanShift 抢风扇）
#      TG Pro 自己的「登录时启动」脚本关不掉，开着的话最后会提示你手动关
#   3. 注释掉 ~/.hammerspoon/init.lua 里的 require("tgpro-hotkey")，重启 Hammerspoon
#      （Hammerspoon 本身和里面的其他脚本都不动）
#   4. 去掉旧的自启项 com.kriswonka.tghotkey.autostart（它会在登录时打开 TG Pro）
#   5. 打开 FanShift 的开机自启，启动 FanShift —— 它会弹窗要求安装后台程序，需要输一次密码
#
# 想退回旧方案：bash scripts/rollback-to-tgpro.sh <备份目录>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP="$HOME/Library/Application Support/FanShift/cutover-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
INIT_LUA="$HOME/.hammerspoon/init.lua"
OLD_AGENT_LABEL="com.kriswonka.tghotkey.autostart"
OLD_AGENT="$HOME/Library/LaunchAgents/${OLD_AGENT_LABEL}.plist"
NEW_AGENT_LABEL="com.kriswonka.fanshift.autostart"
NEW_AGENT="$HOME/Library/LaunchAgents/${NEW_AGENT_LABEL}.plist"
TGPRO_DOMAIN="com.tunabellysoftware.tgpro"

echo "== 1/5 编译并安装 FanShift"
bash "$ROOT/scripts/build-app.sh"
osascript -e 'quit app "FanShift"' >/dev/null 2>&1 || true
for _ in $(seq 1 10); do pgrep -x FanShift >/dev/null || break; sleep 0.3; done
rm -rf /Applications/FanShift.app
cp -R "$ROOT/build/FanShift.app" /Applications/FanShift.app

echo "== 2/5 让 TG Pro 交出风扇"
defaults export "$TGPRO_DOMAIN" "$BACKUP/tgpro-prefs.plist" 2>/dev/null || true
if pgrep -x "TG Pro" >/dev/null; then
    # TG Pro 退出时会用内存里的旧值覆盖偏好设置，所以必须等它完全退出再改
    osascript -e 'with timeout of 20 seconds' -e 'tell application "TG Pro" to quit' -e 'end timeout' >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do pgrep -x "TG Pro" >/dev/null || break; sleep 0.5; done
fi
if pgrep -x "TG Pro" >/dev/null; then
    echo "✗ TG Pro 没有退出，先手动退出它再重新运行本脚本"; exit 1
fi
if defaults read "$TGPRO_DOMAIN" fanControlType >/dev/null 2>&1; then
    defaults write "$TGPRO_DOMAIN" fanControlType -int 0
    defaults write "$TGPRO_DOMAIN" enableSystemOverrides -array -int 0 -int 0
fi
# System Events 不应答时别干等（默认超时 2 分钟）
if osascript -e 'with timeout of 10 seconds' -e 'tell application "System Events" to get the name of every login item' -e 'end timeout' 2>/dev/null | grep -q "TG Pro"; then
    osascript -e 'with timeout of 10 seconds' -e 'tell application "System Events" to delete login item "TG Pro"' -e 'end timeout' >/dev/null 2>&1 || true
    echo "tgpro-login-item" >> "$BACKUP/removed.txt"
fi
# TG Pro 自己的「登录时启动」是它用自带的小助手注册的，不在上面那个列表里，脚本关不掉
TGPRO_AUTOLAUNCH=0
if [ "$(defaults read "$TGPRO_DOMAIN" launchOnLogin 2>/dev/null || echo 0)" = "1" ]; then TGPRO_AUTOLAUNCH=1; fi

echo "== 3/5 停用 Hammerspoon 里的 tgpro-hotkey"
if [ -f "$INIT_LUA" ] && grep -qE '^[[:space:]]*require\("tgpro-hotkey"\)' "$INIT_LUA"; then
    cp "$INIT_LUA" "$BACKUP/init.lua"
    sed -i '' -E 's|^([[:space:]]*)require\("tgpro-hotkey"\)|\1-- require("tgpro-hotkey")  -- 已由 FanShift 接替|' "$INIT_LUA"
    # 对运行中的 Hammerspoon 执行 open 不会重新加载配置，要退干净再开
    if pgrep -x Hammerspoon >/dev/null; then
        osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
        for _ in $(seq 1 10); do pgrep -x Hammerspoon >/dev/null || break; sleep 0.3; done
        pkill -x Hammerspoon 2>/dev/null || true
        open -ga Hammerspoon
    fi
else
    echo "   init.lua 里没有启用 tgpro-hotkey，跳过"
fi

echo "== 4/5 去掉旧的自启项"
if [ -f "$OLD_AGENT" ]; then
    cp "$OLD_AGENT" "$BACKUP/"
    launchctl bootout "gui/$(id -u)/${OLD_AGENT_LABEL}" 2>/dev/null || true
    rm -f "$OLD_AGENT"
fi

echo "== 5/5 打开 FanShift 的开机自启并启动"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$NEW_AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${NEW_AGENT_LABEL}</string>
    <key>RunAtLoad</key><true/>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>/Applications/FanShift.app</string>
    </array>
</dict>
</plist>
EOF
open /Applications/FanShift.app

echo
echo "✅ 切换完成。FanShift 已启动：第一次会弹窗要求安装后台程序，输一次密码即可。"
echo "   备份在：$BACKUP"
echo "   想退回旧方案：bash \"$ROOT/scripts/rollback-to-tgpro.sh\" \"$BACKUP\""
if [ "$TGPRO_AUTOLAUNCH" = "1" ]; then
    echo
    echo "⚠ TG Pro 自己的「登录时启动」还开着，下次登录它还会自己打开（不会再碰风扇，但占菜单栏位置）。"
    echo "   要关：打开 TG Pro → 设置 → 取消 Launch on login；或者 系统设置 → 通用 → 登录项。"
fi
