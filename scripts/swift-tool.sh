#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Some Command Line Tools installations retain old private package interfaces.
# Use their matching public interfaces in a local copy, leaving system files intact.
pm_api="$(xcrun --find swiftc | xargs dirname)/../lib/swift/pm/ManifestAPI"
local_pm="$PWD/.build/package-libs"
mkdir -p "$local_pm/ManifestAPI/PackageDescription.swiftmodule"
cp "$pm_api/libPackageDescription.dylib" "$local_pm/ManifestAPI/"
for file in "$pm_api"/PackageDescription.swiftmodule/*.swiftinterface; do
    case "$file" in *.private.swiftinterface) continue ;; esac
    cp "$file" "$local_pm/ManifestAPI/PackageDescription.swiftmodule/"
done
export SWIFTPM_CUSTOM_LIBS_DIR="$local_pm"
frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
exec swift "$@" --build-system native -Xswiftc -F -Xswiftc "$frameworks" -Xlinker -F -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$frameworks"
