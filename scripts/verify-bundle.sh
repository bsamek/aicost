#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Prove the app uses its own resources, not SwiftPM's absolute build path.
test_dir="$(mktemp -d /tmp/codex-cost-bundle.XXXXXX)"
bundle="$PWD/.build/arm64-apple-macosx/release/CodexCost_CostCore.bundle"
restore() {
    if [ -d "$bundle.hidden" ]; then mv "$bundle.hidden" "$bundle"; fi
    rm -rf "$test_dir"
}
trap restore EXIT
cp -R 'build/Codex Cost.app' "$test_dir/"
if [ -d "$bundle" ]; then mv "$bundle" "$bundle.hidden"; fi
CODEX_HOME="$test_dir/empty-home" CLAUDE_CONFIG_DIR="$test_dir/empty-claude" XDG_DATA_HOME="$test_dir/empty-xdg" "$test_dir/Codex Cost.app/Contents/MacOS/CodexCost" --report > "$test_dir/report.json"
python3 - "$test_dir/report.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['today']['total']=='0' and report['month']['total']=='0'
assert report['files']==0
print('Relocated app loads bundled pricing without the build directory.')
PY
