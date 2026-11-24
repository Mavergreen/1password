#!/usr/bin/env bats
# platform: macOS-only -- pkgbuild, pkgutil and PlistBuddy build and read the .pkg
# The 1Password PRESET .pkg: it ships the parameter set (1password.conf + 1password.menu.json) and
# the bin/op CLI; its postinstall asks Porthole to materialize "Linux 1Password.app". Runs only where
# Apple's pkg tooling exists (the Mavericks dev box and the macOS CI runner).

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PORTHOLE_REPO="${PORTHOLE_DIR:-$REPO/../mavergreen-porthole}"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/op-pkg-test.XXXXXX")"
}
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

@test "the preset .pkg ships op and the preset in its tree, and nothing in /usr/local/bin" {
  run sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  files="$(lsbom -s "$WORK/x/mavericks-1password-component.pkg/Bom")"
  echo "$files" | grep -q 'usr/local/mavergreen/1password/bin/op$'
  echo "$files" | grep -q 'usr/local/mavergreen/1password/share/porthole/presets/1password.conf$'
  echo "$files" | grep -q 'usr/local/mavergreen/1password/share/porthole/presets/1password.menu.json$'
  echo "$files" | grep -q 'usr/local/mavergreen/1password/mavergreen.plist$'
  if echo "$files" | grep -q 'usr/local/bin/'; then false; fi
}

@test "the .pkg declares a 10.9.5 floor, the base first, and the 1password identifier" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  grep -q 'os-version min="10.9.5"' "$WORK/x/Distribution"
  grep -q 'dev.mavergreen.1password' "$WORK/x/Distribution"
  [ "$(sed -n 's/.*<line choice="\([^"]*\)".*/\1/p' "$WORK/x/Distribution" | grep -v '^default$' | head -1)" = dev.mavergreen.base ]
}

@test "the manifest declares the materialized app, so uninstall removes it" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  mkdir -p "$WORK/t"; (cd "$WORK/t" && gzip -dc "$WORK/x/mavericks-1password-component.pkg/Payload" | cpio -id --quiet)
  [ "$(/usr/libexec/PlistBuddy -c 'Print :generated:0' "$WORK/t/usr/local/mavergreen/1password/mavergreen.plist")" = "Applications/Linux 1Password.app" ]
  [ -z "$(/usr/libexec/PlistBuddy -c 'Print :appcast' "$WORK/t/usr/local/mavergreen/1password/mavergreen.plist")" ]
}

# Momiji and PowerFox find the 1Password extension's native host through this machine-wide manifest.
# The package owns both it and the bridge it names, so they move together: a per-user copy written by
# an older op pointed at wherever op lived then, and broke the extension when op moved (2026-09-24, 2026-10-03).
@test "the .pkg installs the browser's native-messaging manifest, naming the bridge it ships" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  mkdir -p "$WORK/t"; (cd "$WORK/t" && gzip -dc "$WORK/x/mavericks-1password-component.pkg/Payload" | cpio -id --quiet)
  m="$WORK/t/Library/Application Support/Mozilla/NativeMessagingHosts/com.1password.1password.json"
  [ -f "$m" ] || return 1
  python -c 'import json,sys
m = json.load(open(sys.argv[1]))
assert m["name"] == "com.1password.1password", m
assert m["type"] == "stdio", m
assert m["path"] == "/usr/local/mavergreen/1password/libexec/op-browser-bridge", m
assert m["allowed_extensions"] == ["{d634138d-c276-4fc8-924b-40a0ea21d284}"], m' "$m" || return 1
  [ -x "$WORK/t/usr/local/mavergreen/1password/libexec/op-browser-bridge" ] || return 1
  [ "$(/usr/libexec/PlistBuddy -c 'Print :outside' "$WORK/t/usr/local/mavergreen/1password/mavergreen.plist" | grep -c 'NativeMessagingHosts/com.1password.1password.json')" -eq 1 ] || return 1
}

@test "the package requires a Porthole with the engine tools its op, bridge and preset use" {
  grep -qF -- "--requires 'porthole>=20261121.0'" "$REPO/packaging/macos/build_pkg.sh"
}

@test "no hand-written requirement check is left to drift" {
  [ ! -e "$REPO/packaging/macos/preinstall-hook.sh" ] || return 1
  ! grep -q -- '--preinstall-hook' "$REPO/packaging/macos/build_pkg.sh" || return 1
}

# The app must exist for the install to count; only the build may be left to the first launch.
@test "postinstall fails when the app can't be materialized" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\n[ "$1" = materialize ] && exit 1\nexit 0\n' > "$e/porthole"; chmod +x "$e/porthole"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -ne 0 ]
}

@test "postinstall materializes the preset from its tree with the target volume's engine" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\necho "$@" >> "%s/args"\n' "$WORK" > "$e/porthole"; chmod +x "$e/porthole"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -eq 0 ]
  c="$WORK/v/usr/local/mavergreen/1password/share/porthole/presets/1password.conf"
  [ "$(sed -n 1p "$WORK/args")" = "materialize $c --apps-dir $WORK/v/Applications" ] || { cat "$WORK/args"; return 1; }
  # ...then builds the app in its own window before Installer finishes (Porthole skips this on another volume).
  [ "$(sed -n 2p "$WORK/args")" = "prepare-for-install --root $WORK/v --apps-dir $WORK/v/Applications $c" ] || { cat "$WORK/args"; return 1; }
}

@test "the .pkg ships 1Password's browser allowlist template in its tree, never in /etc" {
  run sh "$REPO/packaging/macos/build_pkg.sh" 9.9.9 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  files="$(lsbom -s "$WORK"/x/*.pkg/Bom)"
  echo "$files" | grep -qx './usr/local/mavergreen/1password/share/1password/custom_allowed_browsers' \
    || { echo "$files"; return 1; }
  echo "$files" | grep -qx './usr/local/mavergreen/1password/share/1password/preseeded_browsers' \
    || { echo "$files"; return 1; }
  ! echo "$files" | grep -q '^./etc/' || return 1
  t="$REPO/packaging/macos/custom_allowed_browsers"
  grep -q '^# 1Password for Linux custom browser allowlist$' "$t"
  grep -q '^# On a Mac, an entry is the browser application.s name, such as Google Chrome.app$' "$t"
  ! grep -v '^#' "$t" | grep -q . || return 1   # only comments: it allows nothing by itself
}

@test "postinstall installs the allowlist template only when the Mac has no allowlist" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\n' > "$e/porthole"; chmod +x "$e/porthole"
  t="$WORK/v/usr/local/mavergreen/1password/share/1password"; mkdir -p "$t"
  printf '# template\n' > "$t/custom_allowed_browsers"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$WORK/v/etc/1password/custom_allowed_browsers")" = "# template" ]
  [ "$(stat -f %Lp "$WORK/v/etc/1password/custom_allowed_browsers")" = 644 ]
  printf 'Vivaldi.app\n' > "$WORK/v/etc/1password/custom_allowed_browsers"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$(cat "$WORK/v/etc/1password/custom_allowed_browsers")" = "Vivaldi.app" ]
}

@test "a template that can't be installed only warns: the app is still materialized" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\necho "$1" >> "%s/args"\n' "$WORK" > "$e/porthole"; chmod +x "$e/porthole"
  t="$WORK/v/usr/local/mavergreen/1password/share/1password"; mkdir -p "$t"
  printf '# template\n' > "$t/custom_allowed_browsers"; chmod 000 "$t/custom_allowed_browsers"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  chmod 644 "$t/custom_allowed_browsers"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qx materialize "$WORK/args"
  [[ "$output" == *"custom_allowed_browsers"* ]] || { echo "$output"; return 1; }
}

@test "on another volume, the postinstall hook succeeds without touching the running system" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\n' > "$e/porthole"; chmod +x "$e/porthole"
  mkdir -p "$WORK/v/Users/someone/Library/LaunchAgents"; : > "$WORK/v/Users/someone/Library/LaunchAgents/dev.mavergreen.op-ssh-agent.plist"
  mkdir -p "$WORK/stubs"; : > "$WORK/log"
  for t in launchctl open kextstat kextload kextunload killall pkill osascript sudo docker docker-machine porthole op; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/log"\n' "$t" "$WORK" > "$WORK/stubs/$t"; chmod +x "$WORK/stubs/$t"
  done
  for h in postinstall-hook.sh; do
    run env PATH="$WORK/stubs:/usr/bin:/bin" ROOT="$WORK/v" sh "$REPO/packaging/macos/$h"
    [ "$status" -eq 0 ] || { echo "$h: $output"; return 1; }
  done
  [ ! -s "$WORK/log" ] || { cat "$WORK/log"; return 1; }
}

@test "materialize turns the conf into Linux 1Password.app with a menu bar" {
  [ -x "$PORTHOLE_REPO/bin/porthole" ] || skip "porthole engine not available as a sibling"
  PORTHOLE_MATERIALIZE_NO_ICON=1 PORTHOLE_LSREGISTER=true PORTHOLE_ICON_CACHE="$WORK/sys-icons" PORTHOLE_USER_ICON_CACHE="$WORK/user-icons" "$PORTHOLE_REPO/bin/porthole" \
    materialize "$REPO/1password.conf" --apps-dir "$WORK/apps"
  [ -d "$WORK/apps/Linux 1Password.app" ]
  [ -f "$WORK/apps/Linux 1Password.app/Contents/Resources/menu.json" ]
  [ -x "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/1password" ]
  [ -x "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/porthole-recover-watch" ]   # bundled watcher
  # runs its OWN engine binary in place (distinct app), not `open` of a shared Porthole.app
  grep -q 'exec "$_bin" "$XPRA_SOCK"' "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/1password" || return 1
  [ "$(cat "$WORK/apps/Linux 1Password.app/Contents/Resources/AppIcon.width")" = 0 ]   # no cache: the penguin
}

# The release's version goes into the installed conf, so each release changes the app's recipe and
# its install rebuilds the Linux app with the newest package.
@test "the installed conf names the release's version" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  mkdir -p "$WORK/t"; (cd "$WORK/t" && gzip -dc "$WORK/x/mavericks-1password-component.pkg/Payload" | cpio -id --quiet)
  [ "$(tail -n 1 "$WORK/t/usr/local/mavergreen/1password/share/porthole/presets/1password.conf")" = APP_VERSION=0.0.0 ]
}

# A stand-in for the updater mavericks_add_updater_app builds: the identity and feed shipyard's registry
# gives 1password, which stage_product.sh checks.
stub_updater() {
  u="$WORK/1password-updater.app"; mkdir -p "$u/Contents/MacOS"
  printf '#!/bin/sh\n' > "$u/Contents/MacOS/1password-updater"; chmod +x "$u/Contents/MacOS/1password-updater"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.mavergreen.1password.updater' \
    -c 'Add :CFBundleExecutable string 1password-updater' \
    -c 'Add :SUFeedURL string https://github.com/Mavergreen/1password/releases/latest/download/1password.xml' \
    "$u/Contents/Info.plist" >/dev/null
  printf '%s' "$u"
}

# Releases reach an installed preset the way Porthole's do: a daily check, then an offer to install.
@test "with UPD_APP, the pkg carries 1password's updater and its daily check" {
  run env UPD_APP="$(stub_updater)" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  files="$(lsbom -s "$WORK/x/mavericks-1password-component.pkg/Bom")"
  echo "$files" | grep -q 'Library/Application Support/Mavergreen/1password-updater.app/Contents/Info.plist$' || { echo "$files"; return 1; }
  echo "$files" | grep -q 'updatecheck.plist$' || { echo "$files"; return 1; }
}

@test "UPD_APP naming no updater fails the build" {
  run env UPD_APP="$WORK/nothing-here.app" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"no updater .app"* ]] || false
}

# Bad arguments are refused before anything slow or fallible runs (locating shipyard runs cmake), so
# the refusal is the same whatever state shipyard is in -- it flaked once when it wasn't.
@test "UPD_APP naming no updater fails the build even when shipyard can't be located" {
  mkdir -p "$WORK/fakebin"
  printf '#!/bin/sh\necho "refused" >&2\nexit 1\n' > "$WORK/fakebin/shipyard-cmake"; chmod +x "$WORK/fakebin/shipyard-cmake"
  run env -i HOME="$HOME" TMPDIR="$WORK" PATH="$WORK/fakebin:/usr/bin:/bin" UPD_APP="$WORK/nothing-here.app" \
    sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"no updater .app"* ]] || { echo "$output"; false; }
}

@test "build_pkg.sh leaves no temporary directories behind" {
  mkdir -p "$WORK/tmp"
  run env TMPDIR="$WORK/tmp" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$(ls "$WORK/tmp")" ] || { ls "$WORK/tmp"; false; }
  run env TMPDIR="$WORK/tmp" UPD_APP="$WORK/nothing-here.app" sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out2.pkg"
  [ "$status" -ne 0 ] || return 1
  [ -z "$(ls "$WORK/tmp")" ] || { ls "$WORK/tmp"; false; }
}

# The old op installed these to serve the SSH agent and to watch for prompts; the app does both now.
@test "postinstall removes the old op's LaunchAgents, and only those" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\n' > "$e/porthole"; chmod +x "$e/porthole"
  la="$WORK/v/Users/someone/Library/LaunchAgents"; mkdir -p "$la"
  : > "$la/dev.mavergreen.op-ssh-agent.plist"; : > "$la/dev.mavergreen.op-watch.plist"; : > "$la/org.example.keep.plist"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$la/dev.mavergreen.op-ssh-agent.plist" ]
  [ ! -e "$la/dev.mavergreen.op-watch.plist" ]
  [ -e "$la/org.example.keep.plist" ]
}

# The old `op browser connect` wrote a per-user manifest naming `op _browser-bridge`. Firefox reads a
# user's own manifest before the machine-wide one, and op is 1Password's CLI now, with no such
# command: the extension found no app and asked for the password itself.
@test "postinstall removes the old op's per-user browser manifest and its launcher, and only those" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\n' > "$e/porthole"; chmod +x "$e/porthole"
  for u in someone other; do
    mkdir -p "$WORK/v/Users/$u/Library/Application Support/Mozilla/NativeMessagingHosts" "$WORK/v/Users/$u/.config/1p"
  done
  old="$WORK/v/Users/someone/Library/Application Support/Mozilla/NativeMessagingHosts/com.1password.1password.json"
  printf '{\n  "name": "com.1password.1password",\n  "path": "/Users/someone/.config/1p/op-browser-bridge",\n  "type": "stdio"\n}\n' > "$old"
  printf '#!/bin/sh\n# Written by `op browser connect`.\nexec op _browser-bridge "$@"\n' > "$WORK/v/Users/someone/.config/1p/op-browser-bridge"
  mine="$WORK/v/Users/other/Library/Application Support/Mozilla/NativeMessagingHosts/com.1password.1password.json"
  printf '{\n  "name": "com.1password.1password",\n  "path": "/opt/elsewhere/host",\n  "type": "stdio"\n}\n' > "$mine"
  printf '#!/bin/sh\n# my own\n' > "$WORK/v/Users/other/.config/1p/op-browser-bridge"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$old" ] || return 1
  [ ! -e "$WORK/v/Users/someone/.config/1p/op-browser-bridge" ] || return 1
  [ -e "$mine" ] || return 1
  [ -e "$WORK/v/Users/other/.config/1p/op-browser-bridge" ] || return 1
}
