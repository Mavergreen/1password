#!/usr/bin/env bats
# The 1Password PRESET .pkg: it ships the parameter set (1password.conf + 1password.menu.json) and
# the bin/op CLI; its postinstall asks Porthole to materialize "Linux 1Password.app". Runs only where
# Apple's pkg tooling exists (the Mavericks dev box and the macOS CI runner).

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PORTHOLE_REPO="${PORTHOLE_DIR:-$REPO/../mavergreen-porthole}"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/op-pkg-test.XXXXXX")"
}
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

@test "the preset .pkg ships the conf, the menu manifest, and the op CLI + symlink" {
  run sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  files="$(pkgutil --payload-files "$WORK/out.pkg")"
  echo "$files" | grep -q 'Library/Application Support/Mavergreen/Porthole/presets/1password.conf'
  echo "$files" | grep -q 'Library/Application Support/Mavergreen/Porthole/presets/1password.menu.json'
  echo "$files" | grep -q 'usr/local/libexec/mavericks-1password/bin/op'
  echo "$files" | grep -q 'usr/local/bin/op$'
}

@test "the .pkg declares a 10.9.5 floor and the 1password identifier" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  grep -q 'os-version min="10.9.5"' "$WORK/x/Distribution"
  grep -q 'dev.mavergreen.1password' "$WORK/x/Distribution"
}

@test "preinstall refuses to install when Porthole is absent" {
  sed 's#/usr/local/bin/porthole#/nope/porthole#g; s#/Applications/Porthole.app#/nope/Porthole.app#g' \
    "$REPO/packaging/macos/scripts/preinstall" > "$WORK/pre"; chmod 755 "$WORK/pre"
  run sh "$WORK/pre"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs Porthole installed"* ]] || false
}

@test "postinstall invokes porthole materialize on the installed conf" {
  grep -q 'materialize' "$REPO/packaging/macos/scripts/postinstall"
  grep -q '/Library/Application Support/Mavergreen/Porthole/presets/1password.conf' "$REPO/packaging/macos/scripts/postinstall"
}

@test "materialize turns the conf into Linux 1Password.app with a menu bar" {
  [ -x "$PORTHOLE_REPO/bin/porthole" ] || skip "porthole engine not available as a sibling"
  PORTHOLE_MATERIALIZE_NO_ICON=1 "$PORTHOLE_REPO/bin/porthole" \
    materialize "$REPO/1password.conf" --apps-dir "$WORK/apps"
  [ -d "$WORK/apps/Linux 1Password.app" ]
  [ -f "$WORK/apps/Linux 1Password.app/Contents/Resources/menu.json" ]
  [ -x "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/1password" ]
  [ -x "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/porthole-recover-watch" ]   # bundled watcher
  # runs its OWN engine binary in place (distinct app), not `open` of a shared Porthole.app
  grep -q 'exec "$_bin" "$XPRA_SOCK"' "$WORK/apps/Linux 1Password.app/Contents/Resources/bin/1password"
}

# ONE-TIME MIGRATION off the ModernMavericks identity (flag day 2026-09-22).
# DELETABLE with packaging/macos/scripts/flag-day-migration (see shipyard SKILL.md "Consolidation backlog").
fake_pkgutil() {
  mkdir -p "$WORK/stubs"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit %s\n' "$WORK/pkgutil.log" "${1:-0}" > "$WORK/stubs/pkgutil"
  chmod 755 "$WORK/stubs/pkgutil"
}
old_presets() { printf '%s' "$WORK/vol/Library/Application Support/Porthole/presets"; }
migrate() { PATH="$WORK/stubs:$PATH" run sh "$REPO/packaging/macos/scripts/flag-day-migration" "$@"; }

@test "the pkg ships the flag-day migration and postinstall runs it with Installer's arguments" {
  sh "$REPO/packaging/macos/build_pkg.sh" 0.0.0 "$WORK/out.pkg" >/dev/null
  pkgutil --expand "$WORK/out.pkg" "$WORK/x"
  [ -x "$WORK/x/mavericks-1password-component.pkg/Scripts/flag-day-migration" ] \
    || { echo "flag-day-migration is not in the pkg's Scripts, so postinstall cannot run it"; return 1; }
  grep -q 'sh "$(dirname "$0")/flag-day-migration" "$@"' "$REPO/packaging/macos/scripts/postinstall" \
    || { echo "postinstall does not pass its own \$@ (so \$3, the target volume) to flag-day-migration"; return 1; }
}

@test "flag-day migration removes this preset's old files, keeps other presets, forgets the old receipt" {
  fake_pkgutil 0
  mkdir -p "$(old_presets)"
  for f in 1password.conf 1password.menu.json other-app.conf; do : > "$(old_presets)/$f"; done
  migrate pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$(old_presets)/1password.conf" ] || { echo "old 1password.conf left at the pre-flag-day path"; return 1; }
  [ ! -e "$(old_presets)/1password.menu.json" ] || { echo "old 1password.menu.json left at the pre-flag-day path"; return 1; }
  [ -e "$(old_presets)/other-app.conf" ] || { echo "removed ANOTHER preset's file: only our own names may go"; return 1; }
  grep -qx -- "--volume $WORK/vol --forget dev.modernmavericks.1password" "$WORK/pkgutil.log" \
    || { echo "old receipt not forgotten on the target volume; pkgutil saw: $(cat "$WORK/pkgutil.log" 2>/dev/null)"; return 1; }
}

@test "flag-day migration removes the old preset dirs once they are empty" {
  fake_pkgutil 0
  mkdir -p "$(old_presets)"; : > "$(old_presets)/1password.conf"
  migrate pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || return 1
  [ ! -e "$WORK/vol/Library/Application Support/Porthole" ] \
    || { echo "the emptied pre-flag-day Porthole dir was left behind"; return 1; }
  [ -d "$WORK/vol/Library/Application Support" ] || { echo "removed more than the Porthole dir"; return 1; }
}

@test "flag-day migration touches nothing without a target volume, and never fails the install" {
  fake_pkgutil 1
  mkdir -p "$(old_presets)"; : > "$(old_presets)/1password.conf"
  migrate
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/pkgutil.log" ] || { echo "forgot a receipt with no target volume"; return 1; }
  [ -e "$(old_presets)/1password.conf" ] || { echo "removed a file with no target volume"; return 1; }
  migrate pkg "$WORK/vol" "$WORK/vol" "$WORK/vol"
  [ "$status" -eq 0 ] || { echo "a failing pkgutil failed the install"; return 1; }
}
