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

@test "preinstall refuses a volume without Porthole, naming it" {
  mkdir -p "$WORK/v/usr/local/mavergreen/container-tools"; : > "$WORK/v/usr/local/mavergreen/container-tools/mavergreen.plist"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs Porthole installed"* ]] || false
}

@test "preinstall refuses a volume without Container Tools, naming it" {
  mkdir -p "$WORK/v/usr/local/mavergreen/porthole"; : > "$WORK/v/usr/local/mavergreen/porthole/mavergreen.plist"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs Container Tools for Mavericks"* ]] || false
}

@test "preinstall accepts a volume with both, and reads only that volume" {
  for p in porthole container-tools; do mkdir -p "$WORK/v/usr/local/mavergreen/$p"; : > "$WORK/v/usr/local/mavergreen/$p/mavergreen.plist"; done
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/preinstall-hook.sh"
  [ "$status" -eq 0 ]
}

@test "postinstall materializes the preset from its tree with the target volume's engine" {
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\necho "$@" > "%s/args"\n' "$WORK" > "$e/porthole"; chmod +x "$e/porthole"
  run env ROOT="$WORK/v" sh "$REPO/packaging/macos/postinstall-hook.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/args")" = "materialize $WORK/v/usr/local/mavergreen/1password/share/porthole/presets/1password.conf --apps-dir $WORK/v/Applications" ]
}

@test "on another volume, both hooks succeed without touching the running system" {
  for p in porthole container-tools; do mkdir -p "$WORK/v/usr/local/mavergreen/$p"; : > "$WORK/v/usr/local/mavergreen/$p/mavergreen.plist"; done
  e="$WORK/v/Applications/Porthole.app/Contents/Resources/engine/bin"; mkdir -p "$e"
  printf '#!/bin/sh\n' > "$e/porthole"; chmod +x "$e/porthole"
  mkdir -p "$WORK/stubs"; : > "$WORK/log"
  for t in launchctl open kextstat kextload kextunload killall pkill osascript sudo docker docker-machine porthole op; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/log"\n' "$t" "$WORK" > "$WORK/stubs/$t"; chmod +x "$WORK/stubs/$t"
  done
  for h in preinstall-hook.sh postinstall-hook.sh; do
    run env PATH="$WORK/stubs:/usr/bin:/bin" ROOT="$WORK/v" sh "$REPO/packaging/macos/$h"
    [ "$status" -eq 0 ] || { echo "$h: $output"; return 1; }
  done
  [ ! -s "$WORK/log" ] || { cat "$WORK/log"; return 1; }
}

@test "materialize turns the conf into Linux 1Password.app with a menu bar" {
  [ -x "$PORTHOLE_REPO/bin/porthole" ] || skip "porthole engine not available as a sibling"
  PORTHOLE_MATERIALIZE_NO_ICON=1 PORTHOLE_ICON_CACHE="$WORK/sys-icons" PORTHOLE_USER_ICON_CACHE="$WORK/user-icons" "$PORTHOLE_REPO/bin/porthole" \
    materialize "$REPO/1password.conf" --apps-dir "$WORK/apps"
  [ -d "$WORK/apps/Linux 1Password.app" ]
  [ -f "$WORK/apps/Linux 1Password.app/Contents/Resources/menu.json" ]
  [ -x "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/1password" ]
  [ -x "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/porthole-recover-watch" ]   # bundled watcher
  # runs its OWN engine binary in place (distinct app), not `open` of a shared Porthole.app
  grep -q 'exec "$_bin" "$XPRA_SOCK"' "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/1password" || return 1
  [ "$(cat "$WORK/apps/Linux 1Password.app/Contents/Resources/AppIcon.width")" = 0 ]   # no cache: the penguin
}
