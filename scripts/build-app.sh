#!/usr/bin/env bash
# 编译并打包成 build/FanShift.app。加 --install 会装进 /Applications 并启动。
# 后台程序和它的 launchd 配置放在 App 的 Resources 里，由 App 第一次启动时提示安装（要输一次密码）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="FanShift"
BUNDLE_ID="com.kriswonka.fanshift"
DAEMON_LABEL="com.kriswonka.fanshift.daemon"
VERSION="${VERSION:-0.1.0}"
APP_DIR="$ROOT/build/${APP_NAME}.app"

echo "→ swift build -c release"
swift build -c release 2>&1 | grep -E "error|warning: unre|Build complete" || true
BIN_DIR="$(swift build -c release --show-bin-path)"
for bin in FanShiftApp fanshiftd fanshiftctl; do
    [ -x "$BIN_DIR/$bin" ] || { echo "✗ 没有编译出 $bin"; exit 1; }
done

echo "→ 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/FanShiftApp" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/fanshiftd" "$APP_DIR/Contents/Resources/fanshiftd"
cp "$BIN_DIR/fanshiftctl" "$APP_DIR/Contents/Resources/fanshiftctl"
cp "$ROOT/Resources/${DAEMON_LABEL}.plist" "$APP_DIR/Contents/Resources/"
ICON_KEY=""
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    ${ICON_KEY}
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# 没有开发者证书，用本机临时签名（自己用足够）
codesign --force --sign - "$APP_DIR/Contents/Resources/fanshiftd" 2>/dev/null
codesign --force --sign - "$APP_DIR/Contents/Resources/fanshiftctl" 2>/dev/null
codesign --force --sign - "$APP_DIR" 2>/dev/null
echo "✅ 打包完成：$APP_DIR"

if [ "${1:-}" = "--install" ]; then
    DEST="/Applications/${APP_NAME}.app"
    echo "→ 安装到 $DEST"
    osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.3; done
    rm -rf "$DEST"
    cp -R "$APP_DIR" "$DEST"
    open -g "$DEST"
    echo "✅ 已安装并启动。第一次启动会提示安装后台程序（要输一次密码）。"
fi
