#!/bin/sh
# Build the mavericks-1password PRESET .pkg. Ships the 1Password parameter set (1password.conf +
# 1password.menu.json) and the bin/op CLI. Its postinstall asks the installed Porthole engine to
# materialize "Linux 1Password.app"; the container recipe + launcher are rendered there. op resolves
# the shared /Applications/Porthole.app engine + the materialized recipe at runtime. No compiler.
# Usage: build_pkg.sh <version> <out.pkg>
set -eu
VERSION=$1; OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/1pm-preset.XXXXXX")
PRESETS="$ROOT/Library/Application Support/Mavergreen/Porthole/presets"
LIBEXEC="$ROOT/usr/local/libexec/mavericks-1password"
install -d "$PRESETS" "$LIBEXEC/bin" "$ROOT/usr/local/bin"
install -m 0644 "$REPO/1password.conf"      "$PRESETS/1password.conf"
install -m 0644 "$REPO/1password.menu.json" "$PRESETS/1password.menu.json"
install -m 0755 "$REPO/bin/op"              "$LIBEXEC/bin/op"
# op resolves sibling assets via its own real path; a symlink keeps $0-resolution intact.
ln -s ../libexec/mavericks-1password/bin/op "$ROOT/usr/local/bin/op"

COMPONENT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/1pm-pkg.XXXXXX")
mkdir -p "$(dirname "$OUT")"
pkgbuild --root "$ROOT" \
    --identifier dev.mavergreen.1password \
    --version "$VERSION" \
    --scripts "$HERE/scripts" \
    --install-location / \
    "$COMPONENT_DIR/mavericks-1password-component.pkg"

productbuild --distribution "$HERE/distribution.xml" \
    --package-path "$COMPONENT_DIR" \
    "$OUT"

echo "Built $OUT"
