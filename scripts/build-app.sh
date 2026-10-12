#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Local builds use the existing CLT workaround; CI uses SWIFT_TOOL=swift.
swift_tool="${SWIFT_TOOL:-scripts/swift-tool.sh}"
app="$PWD/build/Codex Cost.app"
archs="${APP_ARCHS:-$(uname -m)}"
staging="$(mktemp -d /tmp/codex-cost-build.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Codex Cost.app/Contents/MacOS" "$staging/Codex Cost.app/Contents/Resources"
binaries=()
for arch in $archs; do
    case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
    args=(-c release --product CodexCost --triple "$arch-apple-macosx13.0" --scratch-path "$PWD/.build/app-$arch")
    "$swift_tool" build "${args[@]}" "$@"
    bin_path="$("$swift_tool" build "${args[@]}" "$@" --show-bin-path 2>/dev/null)"
    cp "$bin_path/CodexCost" "$staging/CodexCost-$arch"
    binaries+=("$staging/CodexCost-$arch")
    # Copy complete resource bundles, including pricing added by other providers.
    for resource in "$bin_path"/*.bundle; do
        [ -d "$resource" ] || continue
        destination="$staging/Codex Cost.app/Contents/Resources/$(basename "$resource")"
        if [ -d "$destination" ]; then
            diff -r "$resource" "$destination"
        else
            cp -R "$resource" "$destination"
        fi
    done
done
if [ "${#binaries[@]}" -eq 1 ]; then
    cp "${binaries[0]}" "$staging/Codex Cost.app/Contents/MacOS/CodexCost"
else
    /usr/bin/lipo -create "${binaries[@]}" -output "$staging/Codex Cost.app/Contents/MacOS/CodexCost"
fi
cp Resources/Info.plist "$staging/Codex Cost.app/Contents/Info.plist"
python3 - "$staging/Codex Cost.app/Contents/Info.plist" <<'PLIST'
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
/usr/bin/codesign --force --sign - "$staging/Codex Cost.app"
mkdir -p build
rm -rf "$app"
mv "$staging/Codex Cost.app" "$app"
printf 'Built %s (%s)\n' "$app" "$archs"
