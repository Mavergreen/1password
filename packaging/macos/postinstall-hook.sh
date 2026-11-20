#!/bin/sh
# platform: macOS-only -- runs the installed Porthole engine, which builds a macOS app bundle
# The user's browser allowlist, as 1Password's Linux package does it: the template, only if absent.
_allow="$ROOT/etc/1password/custom_allowed_browsers"
_tmpl="$ROOT/usr/local/mavergreen/1password/share/1password/custom_allowed_browsers"
if [ ! -e "$_allow" ] && [ -f "$_tmpl" ]; then
  # Comments only, so it allows nothing by itself: a failure is worth a note, not a failed install.
  { mkdir -p "$ROOT/etc/1password" && install -m 0644 "$_tmpl" "$_allow"; } \
    || echo "1password postinstall: could not install $_allow from $_tmpl; carrying on" >&2
fi
_porthole="$ROOT/Applications/Porthole.app/Contents/Resources/engine/bin/porthole"
_conf="$ROOT/usr/local/mavergreen/1password/share/porthole/presets/1password.conf"
"$_porthole" materialize "$_conf" --apps-dir "$ROOT/Applications" || exit 1
# Build the app now, in its own window, so its first launch doesn't wait; a failure leaves that to the launch.
"$_porthole" prepare-for-install --root "$ROOT" --apps-dir "$ROOT/Applications" "$_conf" || true
