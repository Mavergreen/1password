#!/bin/sh
# platform: macOS-only -- runs the installed Porthole engine, which builds a macOS app bundle
_porthole="$ROOT/Applications/Porthole.app/Contents/Resources/engine/bin/porthole"
_conf="$ROOT/usr/local/mavergreen/1password/share/porthole/presets/1password.conf"
"$_porthole" materialize "$_conf" --apps-dir "$ROOT/Applications" || exit 1
# Build the app now, in its own window, so its first launch doesn't wait; a failure leaves that to the launch.
"$_porthole" prepare-for-install --root "$ROOT" --apps-dir "$ROOT/Applications" "$_conf" || true
