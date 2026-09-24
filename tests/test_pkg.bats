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
