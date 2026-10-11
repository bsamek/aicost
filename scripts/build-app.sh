#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/swift-tool.sh build -c release --product CodexCost
bin_path="$(scripts/swift-tool.sh build -c release --show-bin-path 2>/dev/null)"
app="$PWD/build/Codex Cost.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/CodexCost" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R "$bin_path/CodexCost_CostCore.bundle" "$app/Contents/Resources/"
/usr/bin/codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
