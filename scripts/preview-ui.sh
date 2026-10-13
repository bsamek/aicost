#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -gt 1 ]; then
    echo "Usage: scripts/preview-ui.sh [output-directory]" >&2
    exit 2
fi

# Capture into a fresh directory by default; no installed app or personal logs involved.
preview_dir="${1:-$PWD/build/ui-previews/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$preview_dir"
preview_dir="$(cd "$preview_dir" && pwd)"
export TOKEN_METER_PREVIEW_DIR="$preview_dir"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$PWD/.build/swift-cache}"
swift_tool="${SWIFT_TOOL:-swift}"

"$swift_tool" test --disable-xctest --enable-swift-testing --disable-sandbox \
    --filter PanelPreviewTests

for appearance in light dark; do
    for state in auto-on auto-off update-available disabled loading error; do
        if [ ! -s "$preview_dir/$appearance-$state.png" ]; then
            echo "Missing native capture: $appearance-$state.png" >&2
            exit 1
        fi
    done
done
printf 'Native UI captures: %s\n' "$preview_dir"
printf 'Inspect the PNGs before claiming visual validation; capture success alone is not a visual review.\n'
