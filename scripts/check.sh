#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep compiler caches in the checkout, including in restricted environments.
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$PWD/.build/swift-cache}"
swift_tool="${SWIFT_TOOL:-swift}"

scripts/format.sh --check
"$swift_tool" test --disable-xctest --enable-swift-testing "$@"
