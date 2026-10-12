#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Run a relocated copy while *all* SwiftPM resources are unavailable.
app="${1:-$PWD/build/Harness.app}"
launch="${2:-}"
test_dir="$(mktemp -d /tmp/codex-cost-bundle.XXXXXX)"
hidden_build=""
app_pid=""
restore() {
    if [ -n "$app_pid" ]; then kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi
    if [ -n "$hidden_build" ]; then
        if [ -e "$PWD/.build" ] || ! mv "$hidden_build" "$PWD/.build"; then
            echo "Could not restore .build; preserved original at $hidden_build" >&2
            return 1
        fi
    fi
    rm -rf "$test_dir"
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp -R "$app" "$test_dir/Harness.app"
if [ -d .build ]; then
    hidden_build="$test_dir/swift-build"
    mv .build "$hidden_build"
fi
export CODEX_HOME="$test_dir/empty-codex"
export CLAUDE_CONFIG_DIR="$test_dir/empty-claude"
export PI_CODING_AGENT_DIR="$test_dir/empty-pi"
export OPENCODE_DATA_DIR="$test_dir/empty-opencode"
export XDG_DATA_HOME="$test_dir/empty-data"
export XDG_CONFIG_HOME="$test_dir/empty-config"
binary="$test_dir/Harness.app/Contents/MacOS/CodexCost"
"$binary" --report > "$test_dir/report.json"
python3 - "$test_dir/report.json" <<'PYTHON'
import json, sys
with open(sys.argv[1]) as stream:
    report = json.load(stream)
assert report['today']['total'] == '0' and report['month']['total'] == '0', report
assert report['files'] == 0, report
print('Relocated app loads bundled pricing without the build directory.')
PYTHON
if [ "$launch" = "--launch" ]; then
    # Direct invocation creates a new instance; never address the user's app by bundle ID.
    "$binary" > "$test_dir/launch.log" 2>&1 &
    app_pid=$!
    sleep 3
    if ! kill -0 "$app_pid" 2>/dev/null; then
        cat "$test_dir/launch.log" >&2
        echo "Relocated menu bar app exited during launch." >&2
        exit 1
    fi
    echo 'Relocated menu bar app stays running after launch.'
fi
