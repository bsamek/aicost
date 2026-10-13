#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Local builds use the existing CLT workaround; CI uses SWIFT_TOOL=swift.
swift_tool="${SWIFT_TOOL:-scripts/swift-tool.sh}"
app="$PWD/build/Harness.app"
staging="$(mktemp -d /tmp/codex-cost-build.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Harness.app/Contents/MacOS" "$staging/Harness.app/Contents/Resources"
args=(-c release --product CodexCost --triple arm64-apple-macosx13.0 --scratch-path "$PWD/.build/app-arm64")
"$swift_tool" build "${args[@]}" "$@"
bin_path="$("$swift_tool" build "${args[@]}" "$@" --show-bin-path 2>/dev/null)"
cp "$bin_path/CodexCost" "$staging/Harness.app/Contents/MacOS/CodexCost"
# Copy complete resource bundles, including pricing added by other providers.
for resource in "$bin_path"/*.bundle; do
    [ -d "$resource" ] || continue
    cp -R "$resource" "$staging/Harness.app/Contents/Resources/"
done
cp Resources/Info.plist "$staging/Harness.app/Contents/Info.plist"
python3 - "$staging/Harness.app/Contents/Info.plist" <<'PLIST'
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
/usr/bin/codesign --force --sign - "$staging/Harness.app"
mkdir -p build
rm -rf "$app"
mv "$staging/Harness.app" "$app"
printf 'Built %s (%s)\n' "$app" "arm64"
