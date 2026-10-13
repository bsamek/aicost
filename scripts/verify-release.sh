#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Usage: verify-release.sh APP VERSION BUILD}"
version="${2:?Missing version}"
build="${3:?Missing build number}"
binary="$app/Contents/MacOS/CodexCost"
archs="$(/usr/bin/lipo -archs "$binary")"
if [ "$archs" != arm64 ]; then
    echo "Expected an arm64-only executable, found: $archs" >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app"
python3 - "$app" "$version" "$build" <<'PYTHON'
import pathlib, plistlib, re, subprocess, sys
app, version, build = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
with (app / 'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert info['CFBundleShortVersionString'] == version, info
assert info['CFBundleVersion'] == build, info
assert info['LSMinimumSystemVersion'] == '13.0', info
# Every source resource must survive packaging, irrespective of provider filenames.
for source in pathlib.Path('Sources').glob('*/Resources/*'):
    if source.is_file():
        matches = list((app / 'Contents/Resources').glob(f'*.bundle/{source.name}'))
        assert len(matches) == 1 and matches[0].read_bytes() == source.read_bytes(), source
arch = 'arm64'
output = subprocess.check_output(['/usr/bin/otool', '-arch', arch, '-l', str(app / 'Contents/MacOS/CodexCost')], text=True)
minimums = []
for command in output.split('Load command'):
    if 'cmd LC_BUILD_VERSION\n' in command:
        assert re.search(r'platform (?:1|MACOS)\b', command), command
        minimums += re.findall(r'\bminos (\d+\.\d+(?:\.\d+)?)', command)
    elif 'cmd LC_VERSION_MIN_MACOSX\n' in command:
        minimums += re.findall(r'\bversion (\d+\.\d+(?:\.\d+)?)', command)
assert minimums, output
assert all(tuple(map(int, v.split('.'))) <= (13, 0, 0) for v in minimums), (arch, minimums)
print(f'Apple Silicon app metadata, macOS 13 deployment targets and resources verified ({version}, build {build}).')
PYTHON
scripts/verify-bundle.sh "$app" --launch
