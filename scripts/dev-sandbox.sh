#!/usr/bin/env bash
# 开发用：起一份隔离的测试副本，和正在用的 FanShift 互不影响。
#   - 演练模式：只把指令打印到日志，不碰风扇
#   - 配置和状态放在 ~/Library/Caches/com.kriswonka.fanshift.sandbox/home，不动真实配置（第一次会从真实配置拷一份过来，快捷键改成 ⌃⌥⌘9）
#   - 换了应用标识，所以不会被「已经有一个在运行」拦下
#   - 可执行文件也改了名（FanShiftSandbox）：系统是按「程序名 + 图标名」记菜单栏图标位置的，
#     和正在用的那份同名的话，两边会共用同一份记录，测试时把记录弄坏，正在用的那份图标就被系统藏起来
#   - 调试开关打开：带曲线的档位默认展开；kill -USR1 <pid> 相当于按一次快捷键
# 用法：bash scripts/dev-sandbox.sh        启动（会先重新打包）
#       bash scripts/dev-sandbox.sh stop   退出并清理
#       SNAPSHOTS=1 bash scripts/dev-sandbox.sh   启动并把各页和菜单栏项渲染成 PNG
#       LANG_CODE=es bash scripts/dev-sandbox.sh   用指定的界面语言启动（en / zh-Hans / zh-Hant / es，会写进测试副本的配置）
# 日志和进程号在同一个目录下的 log.txt 和 pid，启动后会打印出来
# 注意：别动测试副本里的「登录时自动启动」开关，它改的是真实的自启项。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 不放在仓库目录里：仓库在「文稿」下面，系统不让启动服务往那里写日志，副本会启动失败（错误 -10810）
BOX="$HOME/Library/Caches/com.kriswonka.fanshift.sandbox"
APP="$BOX/FanShiftSandbox.app"
TEST_ID="com.kriswonka.fanshift.sandbox"

stop() {
    [ -f "$BOX/pid" ] && kill "$(cat "$BOX/pid")" 2>/dev/null || true
    rm -f "$BOX/pid"
}

if [ "${1:-}" = "stop" ]; then
    stop
    rm -rf "$APP" "$BOX/log.txt"
    defaults delete "$TEST_ID" 2>/dev/null || true
    echo "已退出测试副本"
    exit 0
fi

bash "$ROOT/scripts/build-app.sh" | grep -E "error|打包完成" || true
stop
sleep 1
mkdir -p "$BOX/home"
rm -rf "$APP"
cp -R "$ROOT/build/FanShift.app" "$APP"
mv "$APP/Contents/MacOS/FanShift" "$APP/Contents/MacOS/FanShiftSandbox"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $TEST_ID" -c "Set :CFBundleName FanShiftSandbox" \
    -c "Set :CFBundleDisplayName FanShiftSandbox" -c "Set :CFBundleExecutable FanShiftSandbox" "$APP/Contents/Info.plist"
# 测试副本的菜单栏图标放在最左边（数值越大越靠左）。放在正式那份右边的话，菜单栏一挤，
# 被系统藏起来的就是正式那份的图标
for role in readout letter; do
    defaults read "$TEST_ID" "MenuBarPosition.$role" >/dev/null 2>&1 || defaults write "$TEST_ID" "MenuBarPosition.$role" -float 2000
done
codesign --force --sign - "$APP" 2>/dev/null

REAL_CONFIG="$HOME/Library/Application Support/FanShift/config.json"
if [ ! -f "$BOX/home/config.json" ] && [ -f "$REAL_CONFIG" ]; then
    /usr/bin/python3 - "$REAL_CONFIG" "$BOX/home/config.json" <<'PY'
import json, sys
config = json.load(open(sys.argv[1], encoding="utf-8"))
config["hotkeyKey"] = "9"          # 别和正在用的那份抢 ⌃⌥⌘8
config.pop("hotkeyKeyCode", None)
json.dump(config, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
fi

if [ -n "${LANG_CODE:-}" ] && [ -f "$BOX/home/config.json" ]; then
    /usr/bin/python3 - "$BOX/home/config.json" "$LANG_CODE" <<'PY'
import json, sys
config = json.load(open(sys.argv[1], encoding="utf-8"))
config["language"] = sys.argv[2]
json.dump(config, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
fi
: > "$BOX/log.txt"
# SNAPSHOTS=1：启动几秒后把设置窗口各页、屏幕提示、菜单栏项渲染成 PNG，存到 $BOX/snapshots
EXTRA=()
if [ "${SNAPSHOTS:-}" = "1" ]; then
    rm -rf "$BOX/snapshots"
    EXTRA=(--env "FANSHIFT_SNAPSHOT_DIR=$BOX/snapshots")
fi
open --env "FANSHIFT_HOME=$BOX/home" --env FANSHIFT_DRYRUN=1 --env FANSHIFT_DEBUG=1 ${EXTRA[@]+"${EXTRA[@]}"} \
    --stderr "$BOX/log.txt" --stdout "$BOX/log.txt" "$APP"
sleep 3
pgrep -x FanShiftSandbox | head -1 > "$BOX/pid" || true
open "$APP"   # 再打开一次 = 显示设置窗口
echo "测试副本已启动，进程号 $(cat "$BOX/pid" 2>/dev/null || echo 未知)，日志 $BOX/log.txt"
