#!/bin/sh
# platform: macOS-only -- pkgbuild and productbuild assemble the pkg
#   usage: build_pkg.sh <version> <out.pkg>
#          The 1Password preset: op and the preset conf in the product's tree. Its postinstall asks
#          the installed Porthole to materialize "Linux 1Password.app", which the manifest declares
#          as generated so uninstall removes it. The browsers' machine-wide native-messaging manifest
#          names the bridge in the tree, so the 1Password extension reaches the app with no setup.
#          UPD_APP, when set, is the Sparkle updater (build/build-updater.sh) to stage with its daily check.
set -eu
VERSION=$1; OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
. "$REPO/build/msc.sh"

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/1pm-preset.XXXXXX")
T="$ROOT/usr/local/mavergreen/1password"
install -d "$T/bin" "$T/libexec" "$T/share/porthole/presets"
install -m 0644 "$REPO/1password.conf"      "$T/share/porthole/presets/1password.conf"
# The release's version is part of the app's recipe: installing a release rebuilds the Linux app.
printf 'APP_VERSION=%s\n' "$VERSION" >> "$T/share/porthole/presets/1password.conf"
install -m 0644 "$REPO/1password.menu.json" "$T/share/porthole/presets/1password.menu.json"
install -m 0755 "$REPO/bin/op"              "$T/bin/op"
install -m 0755 "$HERE/op-browser-bridge"   "$T/libexec/op-browser-bridge"
NMH="$ROOT/Library/Application Support/Mozilla/NativeMessagingHosts"
install -d "$NMH"
install -m 0644 "$HERE/com.1password.1password.json" "$NMH/com.1password.1password.json"

SCR=$(mktemp -d "${TMPDIR:-/tmp}/1pm-scripts.XXXXXX")
set -- --stage "$ROOT" --product 1password --name "1Password for Mavericks" \
  --version "$VERSION" --generated "Applications/Linux 1Password.app" \
  --requires porthole --postinstall-hook "$HERE/postinstall-hook.sh" \
  --scripts-out "$SCR"
# The Sparkle updater (build/build-updater.sh), and its daily check: releases reach installed Macs.
if [ -n "${UPD_APP:-}" ]; then
  [ -d "$UPD_APP" ] || { echo "build_pkg: UPD_APP set but no updater .app at $UPD_APP" >&2; exit 1; }
  set -- "$@" --updater-app "$UPD_APP"
fi
sh "$SHIPYARD/stage_product.sh" "$@"

COMPONENT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/1pm-pkg.XXXXXX")
pkgbuild --root "$ROOT" --identifier dev.mavergreen.1password --version "$VERSION" \
    --scripts "$SCR" --install-location / "$COMPONENT_DIR/mavericks-1password-component.pkg"

mkdir -p "$(dirname "$OUT")"
sh "$SHIPYARD/set_install_floor.sh" --identifier dev.mavergreen.1password --title "1Password for Mavericks" \
  --component "$COMPONENT_DIR/mavericks-1password-component.pkg" --out "$OUT" --require-scripts >&2

echo "Built $OUT"
