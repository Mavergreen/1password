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
# The old op's LaunchAgents (its SSH agent, its prompt watcher) are gone with it: the app serves the
# agent while its own setting says so, and its prompts come forward themselves. Each user's are
# removed; on the running system the console user's are unloaded first (10.9 has no launchctl
# asuser: bsexec into their session).
for _p in "$ROOT"/Users/*/Library/LaunchAgents/dev.mavergreen.op-ssh-agent.plist \
          "$ROOT"/Users/*/Library/LaunchAgents/dev.mavergreen.op-watch.plist; do
  [ -f "$_p" ] || continue
  if [ -z "$ROOT" ] || [ "$ROOT" = / ]; then
    _u=$(stat -f %Su "$_p")
    _lw=$(pgrep -u "$_u" loginwindow 2>/dev/null | head -n 1)
    [ -z "$_lw" ] || launchctl bsexec "$_lw" sudo -u "$_u" launchctl unload "$_p" >/dev/null 2>&1 || :
    # The agent's s6 server outlives its unloaded job. (A server Porthole's follower runs exits too;
    # the follower serves again on its next check.)
    case $_p in *op-ssh-agent.plist) pkill -u "$_u" -f 'porthole-standin-bridge [^ ]* ssh-agent ' 2>/dev/null || : ;; esac
  fi
  rm -f "$_p"
done
# The old `op browser connect` wrote each user a manifest naming its launcher, `op _browser-bridge`.
# Firefox reads a user's own manifest before this package's machine-wide one, and op is 1Password's
# CLI now, with no such command, so the extension found no app. Only those two files go.
for _h in "$ROOT"/Users/*; do
  _m="$_h/Library/Application Support/Mozilla/NativeMessagingHosts/com.1password.1password.json"
  [ -f "$_m" ] && grep -q '/\.config/1p/op-browser-bridge"' "$_m" && rm -f "$_m"
  _b="$_h/.config/1p/op-browser-bridge"
  [ -f "$_b" ] && grep -q '^# Written by `op browser connect`\.$' "$_b" && rm -f "$_b"
done
_porthole="$ROOT/Applications/Porthole.app/Contents/Resources/engine/bin/porthole"
_conf="$ROOT/usr/local/mavergreen/1password/share/porthole/presets/1password.conf"
"$_porthole" materialize "$_conf" --apps-dir "$ROOT/Applications" || exit 1
# Build the app now, in its own window, so its first launch doesn't wait; a failure leaves that to the launch.
"$_porthole" prepare-for-install --root "$ROOT" --apps-dir "$ROOT/Applications" "$_conf" || true
