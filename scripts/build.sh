#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/ClipLite.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$BIN" "$RES"

swiftc \
  -O \
  -framework AppKit \
  -framework Carbon \
  "$ROOT/Sources/main.swift" \
  -o "$BIN/ClipLite"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$BIN/ClipLite"
codesign --force --deep --sign - "$APP" >/dev/null

echo "$APP"
