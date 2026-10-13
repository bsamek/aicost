#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Local builds use the existing CLT workaround; CI uses SWIFT_TOOL=swift.
swift_tool="${SWIFT_TOOL:-scripts/swift-tool.sh}"
app="$PWD/build/Token Meter.app"
staging="$(mktemp -d /tmp/codex-cost-build.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Token Meter.app/Contents/MacOS" "$staging/Token Meter.app/Contents/Resources"
args=(-c release --product CodexCost --triple arm64-apple-macosx13.0 --scratch-path "$PWD/.build/app-arm64")
"$swift_tool" build "${args[@]}" "$@"
bin_path="$("$swift_tool" build "${args[@]}" "$@" --show-bin-path 2>/dev/null)"
cp "$bin_path/CodexCost" "$staging/Token Meter.app/Contents/MacOS/CodexCost"
# Copy complete resource bundles, including pricing added by other providers.
for resource in "$bin_path"/*.bundle; do
    [ -d "$resource" ] || continue
    cp -R "$resource" "$staging/Token Meter.app/Contents/Resources/"
done
# Preserve the framework's versioned symlinks, helper apps and XPC services.
framework="$PWD/.build/app-arm64/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$framework" ] || { echo 'Sparkle framework not found in SwiftPM artifacts.' >&2; exit 1; }
mkdir -p "$staging/Token Meter.app/Contents/Frameworks"
/usr/bin/ditto "$framework" "$staging/Token Meter.app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$staging/Token Meter.app/Contents/Info.plist"
python3 - "$staging/Token Meter.app/Contents/Info.plist" <<'PLIST'
import os, plistlib, re, sys
path = sys.argv[1]
with open(path, 'rb') as stream:
    info = plistlib.load(stream)
version = os.environ.get('APP_VERSION', info['CFBundleShortVersionString'])
build = os.environ.get('APP_BUILD_VERSION', info['CFBundleVersion'])
if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
    raise SystemExit('APP_VERSION must be a numeric major.minor[.patch] version')
if not re.fullmatch(r'[0-9]+', build):
    raise SystemExit('APP_BUILD_VERSION must be a nonnegative integer')
info['CFBundleShortVersionString'] = version
info['CFBundleVersion'] = build
with open(path, 'wb') as stream:
    plistlib.dump(info, stream)
PLIST
# Sign nested code inside out; do not rely on codesign --deep for signing.
sparkle="$staging/Token Meter.app/Contents/Frameworks/Sparkle.framework/Versions/B"
for helper in "$sparkle/Autoupdate" "$sparkle/Updater.app" "$sparkle/XPCServices/Downloader.xpc" "$sparkle/XPCServices/Installer.xpc"; do
    /usr/bin/codesign --force --sign - "$helper"
done
/usr/bin/codesign --force --sign - "$staging/Token Meter.app/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign --force --sign - "$staging/Token Meter.app"
mkdir -p build
rm -rf "$app"
mv "$staging/Token Meter.app" "$app"
printf 'Built %s (%s)\n' "$app" "arm64"
