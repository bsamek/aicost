#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: package-release.sh VERSION [BUILD] [SWIFT_BUILD_ARGUMENTS...]}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Release version must be major.minor.patch (optionally prefixed with v).' >&2
    exit 1
fi
build="${2:-0}"
if [[ ! "$build" =~ ^[0-9]+$ ]]; then
    echo 'Release build number must be a nonnegative integer.' >&2
    exit 1
fi
shift
if [ "$#" -gt 0 ]; then shift; fi
export APP_VERSION="$version" APP_BUILD_VERSION="$build" APP_ARCHS='arm64 x86_64'
scripts/build-app.sh "$@"
app="$PWD/build/Harness.app"
scripts/verify-release.sh "$app" "$version" "$build"
rm -rf build/release
mkdir -p build/release
archive="Harness-$version-universal.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "build/release/$archive"
# Verify the actual download after extraction, including its signature and startup.
extracted="$(mktemp -d /tmp/codex-cost-release.XXXXXX)"
trap 'rm -rf "$extracted"' EXIT
/usr/bin/ditto -x -k "build/release/$archive" "$extracted"
scripts/verify-release.sh "$extracted/Harness.app" "$version" "$build"
(cd build/release && shasum -a 256 "$archive" > "$archive.sha256")
cat > build/release/RELEASE-NOTES.md <<NOTES
Harness $version (build $build) — macOS 13 or later, Apple Silicon and Intel.

Download \`$archive\`, unzip it, and drag \`Harness.app\` into Applications. Open the app; its total appears in the menu bar. No Swift tools or API key are required.

This release uses an ad-hoc signature. It is **not Developer ID signed or notarized by Apple**. macOS may block the first launch. If you trust this download, try opening the app, then use System Settings → Privacy & Security → Open Anyway and confirm Open. See [Apple's instructions](https://support.apple.com/102445). Do not disable Gatekeeper globally.

The adjacent SHA-256 file lets you check the downloaded ZIP with \`shasum -a 256 -c $archive.sha256\` in the download folder. It verifies file integrity, not developer identity.

Build source: \`$(git rev-parse HEAD)\`. Public Release creation is gated on passing tests, universal architecture/deployment checks, bundled-resource checks and relocated startup validation. The workflow tests startup on its runner's native architecture; macOS 13 and the other architecture are checked in binary metadata, not on physical Macs.
NOTES
printf 'Validated release archive: %s\n' "build/release/$archive"
