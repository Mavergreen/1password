#!/bin/sh
# platform: host-agnostic -- the pinned clang22 cross-builds the Cocoa updater against the 10.9 SDK, on a Mac or Linux
#   usage: build-updater.sh VERSION OUT.app
#          Builds 1password-updater.app for x86_64 and 10.9, carrying VERSION (the release's version,
#          which Sparkle compares with the feed's), out of the source tree, with the clang22 that
#          components/clang22/version pins (shipyard's fetch_clang22.sh) and shipyard's
#          MavericksToolchain.cmake. On Linux the runner's cmake configures (there is no shipyard-cmake
#          there; MavericksShipyard_DIR points find_package at shipyard), elsewhere shipyard-cmake.
set -eu
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
ver="${1:?usage: build-updater.sh VERSION OUT.app}"
out="${2:?usage: build-updater.sh VERSION OUT.app}"
if [ "$(uname -s)" = Linux ]; then SC="$(command -v cmake)"
else SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"; fi
app="$(basename "$(sh "$SHIPYARD/product-name.sh" updater-app 1password)")"
SY="$(cd "$SHIPYARD/.." && pwd)"
tc="$SY/MavericksToolchain.cmake"
[ -f "$tc" ] || { echo "build-updater: no MavericksToolchain.cmake beside $SHIPYARD" >&2; exit 1; }
CL="$(sh "$SHIPYARD/fetch_clang22.sh" "$MAVERICKS_ROOT/components/clang22")" \
  || { echo "build-updater: no pinned clang22 (components/clang22/version)" >&2; exit 1; }
# The compat guard reads the built Mach-O with clang22's readers, which every host has.
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; export LIPO OTOOL NM
b="${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/onep-build/updater"
rm -rf "$b"
"$SC" -S "$MAVERICKS_ROOT" -B "$b" -DONEP_VERSION="$ver" -DCMAKE_TOOLCHAIN_FILE="$tc" \
  -DMavericksShipyard_DIR="$SY" -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 \
  -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.9 \
  -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld64.lld"
"$SC" --build "$b"
rm -rf "$out"
cp -R "$b/$app" "$out"
