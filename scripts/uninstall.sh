#!/bin/zsh
set -euo pipefail

pkill -x ClipLite 2>/dev/null || true
pkill -x ClipLite2 2>/dev/null || true
rm -rf /Applications/ClipLite.app
rm -rf /Applications/ClipLite2.app
rm -rf "$HOME/Library/Application Support/ClipLite"
rm -rf "$HOME/Library/Application Support/ClipLite2"

tccutil reset Accessibility com.local.cliplite 2>/dev/null || true
tccutil reset Accessibility com.local.cliplite2 2>/dev/null || true
tccutil reset Accessibility ClipLite 2>/dev/null || true
tccutil reset Accessibility ClipLite2 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/ClipLite.app 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/ClipLite2.app 2>/dev/null || true

echo "Removed ClipLite/ClipLite2 app, local history, and Accessibility TCC entries."
echo "If old ClipLite entries still appear under Login Items & Background Items, remove them manually in System Settings."
