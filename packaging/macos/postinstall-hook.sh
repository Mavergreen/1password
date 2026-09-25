#!/bin/sh
# platform: macOS-only -- runs the installed Porthole engine, which builds a macOS app bundle
"$ROOT/Applications/Porthole.app/Contents/Resources/engine/bin/porthole" materialize \
  "$ROOT/usr/local/mavergreen/1password/share/porthole/presets/1password.conf" --apps-dir "$ROOT/Applications"
