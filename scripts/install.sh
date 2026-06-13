#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/build/ClipLite.app"
APP_DST="/Applications/ClipLite2.app"

"$ROOT/scripts/build.sh" >/dev/null
pkill -x ClipLite 2>/dev/null || true
pkill -x ClipLite2 2>/dev/null || true
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
open "$APP_DST"

echo "$APP_DST"
echo "If macOS still asks for Accessibility permission, remove old ClipLite entries from System Settings > Privacy & Security > Accessibility, then use /Applications/ClipLite2.app."
