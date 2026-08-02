#!/usr/bin/env bats
# Verify the macOS .pkg assembles correctly: payload layout, the /usr/local/bin
# symlink, the 10.9 install floor, and the identifier. Runs only where Apple's
# pkg tooling exists (the Mavericks dev box and the macos CI runner).

setup() {
  command -v pkgbuild >/dev/null 2>&1 || skip "pkgbuild not available (macOS only)"
  command -v productbuild >/dev/null 2>&1 || skip "productbuild not available"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/1pm-pkgtest.XXXXXX")"
  PKG="$WORK/out.pkg"
}

teardown() { rm -rf "$WORK"; }

@test "build_pkg.sh yields a pkg with the expected payload, symlink, floor, id" {
  run sh "$REPO/packaging/macos/build_pkg.sh" 9.9.9 "$PKG"
  [ "$status" -eq 0 ] || return 1
  [ -f "$PKG" ] || return 1

  files="$(pkgutil --payload-files "$PKG")"
  [[ "$files" == *"usr/local/libexec/mavericks-1password/bin/op"* ]] || return 1
  [[ "$files" == *"usr/local/libexec/mavericks-1password/bin/porthole-recover-watch"* ]] || return 1
  [[ "$files" == *"usr/local/libexec/mavericks-1password/1password/Dockerfile"* ]] || return 1
  [[ "$files" == *"usr/local/libexec/mavericks-1password/1password/start-1password-gui.sh"* ]] || return 1
  [[ "$files" == *"usr/local/bin/op"* ]] || return 1

  pkgutil --expand "$PKG" "$WORK/expand"
  dist="$(cat "$WORK/expand/Distribution")"
  [[ "$dist" == *'os-version min="10.9"'* ]] || return 1
  [[ "$dist" == *'dev.modernmavericks.1password'* ]] || return 1
}
