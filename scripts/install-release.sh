#!/bin/bash
# Download the latest FanShift release and put it in /Applications.
#   curl -fsSL https://raw.githubusercontent.com/KrisWonka/FanShift/main/scripts/install-release.sh | bash
# Files downloaded with curl carry no quarantine flag, so macOS opens the app without asking.
# For testing: FANSHIFT_INSTALL_DIR=<folder> installs somewhere else, FANSHIFT_NO_OPEN=1 skips launching.
set -euo pipefail

REPO="KrisWonka/FanShift"
DEST_DIR="${FANSHIFT_INSTALL_DIR:-/Applications}"
APP="$DEST_DIR/FanShift.app"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "FanShift needs a Mac with Apple silicon." >&2
    exit 1
fi
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
    echo "FanShift needs macOS 14 or later (this Mac has $(sw_vers -productVersion))." >&2
    exit 1
fi

echo "→ Finding the latest release"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
if [ -z "$URL" ]; then
    echo "Could not find a download on https://github.com/$REPO/releases" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "→ Downloading $(basename "$URL")"
curl -fL --progress-bar -o "$TMP/FanShift.zip" "$URL"
ditto -x -k "$TMP/FanShift.zip" "$TMP"
[ -d "$TMP/FanShift.app" ] || { echo "The download does not contain FanShift.app" >&2; exit 1; }

# Quit a running copy before replacing it. The fans go back to the system until the new copy starts.
if [ "$DEST_DIR" = "/Applications" ] && pgrep -x FanShift >/dev/null; then
    echo "→ Quitting the running FanShift"
    osascript -e 'with timeout of 10 seconds' -e 'tell application "FanShift" to quit' -e 'end timeout' >/dev/null 2>&1 || true
    sleep 1
fi

SUDO=""
if [ ! -w "$DEST_DIR" ] || { [ -e "$APP" ] && [ ! -w "$APP" ]; }; then
    echo "→ $DEST_DIR is not writable for you; asking for your password"
    SUDO="sudo"
fi
$SUDO rm -rf "$APP"
$SUDO ditto "$TMP/FanShift.app" "$APP"
$SUDO xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✅ Installed $APP"
if [ -z "${FANSHIFT_NO_OPEN:-}" ]; then
    open "$APP"
    echo "   On first launch FanShift asks to install its background helper, which needs your admin password once."
fi
