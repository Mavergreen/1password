#!/bin/sh
# platform: macOS-only -- builds a Cocoa app with shipyard-cmake
#   usage: build-updater.sh VERSION OUT.app
#          Builds 1password-updater.app for x86_64 and 10.9, carrying VERSION (the release's version,
#          which Sparkle compares with the feed's), out of the source tree.
set -eu
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
ver="${1:?usage: build-updater.sh VERSION OUT.app}"
out="${2:?usage: build-updater.sh VERSION OUT.app}"
SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
app="$(basename "$(sh "$SHIPYARD/product-name.sh" updater-app 1password)")"
tc="$SHIPYARD/../MavericksToolchain.cmake"
[ -f "$tc" ] || { echo "build-updater: no MavericksToolchain.cmake beside $SHIPYARD" >&2; exit 1; }
b="${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/onep-build/updater"
"$SC" -S "$MAVERICKS_ROOT" -B "$b" -DONEP_VERSION="$ver" \
  -DCMAKE_OBJC_COMPILER=/usr/bin/clang -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 -DCMAKE_TOOLCHAIN_FILE="$tc"
"$SC" --build "$b"
rm -rf "$out"
cp -R "$b/$app" "$out"
