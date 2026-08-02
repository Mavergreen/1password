#!/bin/sh
# Build the mavericks-1password .pkg from the repo's bin/op + 1password/ build context.
# Usage: build_pkg.sh <version> <out.pkg>
set -eu
VERSION=$1; OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

# Stage the payload exactly as it should land on disk.
# BSD mktemp (all macOS, incl. 10.9) requires an explicit template.
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/1pm-root.XXXXXX")
LIBEXEC="$ROOT/usr/local/libexec/mavericks-1password"
install -d "$LIBEXEC/bin" "$LIBEXEC/1password" "$ROOT/usr/local/bin"
install -m 0755 "$REPO/bin/op"                       "$LIBEXEC/bin/op"
install -m 0755 "${PORTHOLE_DIR:-$REPO/../mavericks-porthole}/bin/porthole-recover-watch"     "$LIBEXEC/bin/porthole-recover-watch"
install -m 0644 "$REPO/1password/Dockerfile"             "$LIBEXEC/1password/Dockerfile"
install -m 0755 "$REPO/1password/start-1password-gui.sh" "$LIBEXEC/1password/start-1password-gui.sh"
install -m 0755 "$REPO/1password/1password-child.sh"     "$LIBEXEC/1password/1password-child.sh"
install -m 0644 "$REPO/1password/mac-fonts.conf"         "$LIBEXEC/1password/mac-fonts.conf"
# op finds 1password/ by resolving this relative symlink to bin/op, then ../1password.
ln -s ../libexec/mavericks-1password/bin/op "$ROOT/usr/local/bin/op"

COMPONENT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/1pm-pkg.XXXXXX")
pkgbuild --root "$ROOT" \
    --identifier dev.modernmavericks.1password \
    --version "$VERSION" \
    --scripts "$HERE/scripts" \
    --install-location / \
    "$COMPONENT_DIR/mavericks-1password-component.pkg"

productbuild --distribution "$HERE/distribution.xml" \
    --package-path "$COMPONENT_DIR" \
    "$OUT"

echo "Built $OUT"
