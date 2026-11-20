#!/usr/bin/env bats
# platform: host-agnostic
# op _browser-bridge: the 1Password extension's native host, run through the package's bridge.

load test_helper

# Each Mac browser reaches 1Password as itself: Porthole's porthole-standin-run runs the helper as
# the child of a stand-in at the browser's own path, which 1Password checks against its allowlist.
@test "_browser-bridge runs the helper under the calling browser's stand-in, with the extension id" {
  run "$OP" _browser-bridge /path/to/manifest.json '{d634138d-c276-4fc8-924b-40a0ea21d284}' </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qx "porthole-standin-run 1password-gui -u 1000:0 -e HOME=/home/onepassword -e XDG_RUNTIME_DIR=/run/user/1000 -- /opt/1Password/1Password-BrowserSupport {d634138d-c276-4fc8-924b-40a0ea21d284}" "$STUB_LOG" \
    || { cat "$STUB_LOG"; return 1; }
}

@test "the container allowlist is written as root, before the helper runs, with the pre-seeded browsers" {
  run "$OP" _browser-bridge '{id}' </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '^docker exec -i -u 0 1password-gui sh -c ' "$STUB_LOG" || { cat "$STUB_LOG"; return 1; }
  grep -q 'mv -f /etc/1password/custom_allowed_browsers.new /etc/1password/custom_allowed_browsers$' "$STUB_LOG"
  # written before the helper starts
  w=$(grep -n '^docker exec -i -u 0 ' "$STUB_LOG" | head -1 | cut -d: -f1)
  r=$(grep -n '^porthole-standin-run' "$STUB_LOG" | cut -d: -f1)
  [ "$w" -lt "$r" ]
  printf 'Momiji.app\nMomiji-Stable.app\nMomiji-Rolling.app\nPowerFox.app\nChromium.app\nSafari.app\n' \
    | diff -u - "$STUB_DIR/allowlist.in"
}

@test "the browser's stdin goes only to the helper, never to the allowlist write" {
  printf 'native-message' | "$OP" _browser-bridge '{id}'
  ! grep -q native-message "$STUB_DIR/allowlist.in"
  grep -q 'native-message' "$STUB_DIR/standin-run.in"
}

@test "a root-owned Mac allowlist adds its entries; comments and blank lines are dropped" {
  f="$BATS_TEST_TMPDIR/allowed"; printf '# a comment\n\n  Google Chrome.app  \nVivaldi.app\n' > "$f"
  mkdir -p "$BATS_TEST_TMPDIR/s"; printf '#!/bin/sh\necho "0 644"\n' > "$BATS_TEST_TMPDIR/s/stat"
  chmod +x "$BATS_TEST_TMPDIR/s/stat"
  PATH="$BATS_TEST_TMPDIR/s:$PATH" ONEP_MAC_BROWSER_ALLOWLIST="$f" run "$OP" _browser-bridge '{id}' </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  tail -2 "$STUB_DIR/allowlist.in" | diff -u - <(printf 'Google Chrome.app\nVivaldi.app\n')
}

@test "a Mac allowlist anyone but root could write is ignored, with a note" {
  f="$BATS_TEST_TMPDIR/allowed"; printf 'Evil.app\n' > "$f"
  ONEP_MAC_BROWSER_ALLOWLIST="$f" run "$OP" _browser-bridge '{id}' </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -q Evil.app "$STUB_DIR/allowlist.in"
  [[ "$output" == *"ignoring $f"* ]] || { echo "$output"; return 1; }
}

@test "the root-owned Mac allowlist must not be writable by group or others" {
  f="$BATS_TEST_TMPDIR/allowed"; printf 'Evil.app\n' > "$f"
  mkdir -p "$BATS_TEST_TMPDIR/s"; printf '#!/bin/sh\necho "0 666"\n' > "$BATS_TEST_TMPDIR/s/stat"
  chmod +x "$BATS_TEST_TMPDIR/s/stat"
  PATH="$BATS_TEST_TMPDIR/s:$PATH" ONEP_MAC_BROWSER_ALLOWLIST="$f" run "$OP" _browser-bridge '{id}' </dev/null
  [ -f "$STUB_DIR/allowlist.in" ] || return 1
  ! grep -q Evil.app "$STUB_DIR/allowlist.in"
}

@test "an engine without porthole-standin-run is refused and says to reinstall Porthole" {
  mkdir -p "$BATS_TEST_TMPDIR/engine"
  cp "${BATS_TEST_DIRNAME}/stubs/s6-ipcserver" "$BATS_TEST_TMPDIR/engine/"
  ONEP_S6_IPCSERVER="$BATS_TEST_TMPDIR/engine/s6-ipcserver" run "$OP" _browser-bridge '{id}' </dev/null
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"porthole-standin-run"*"reinstall Porthole"* ]] || { echo "$output"; return 1; }
}

@test "no socat is left in op or the preset (outside comments)" {
  ! grep -hv '^[[:space:]]*#' "$OP" "${BATS_TEST_DIRNAME}/../1password.conf" | grep -n socat
}

# The package installs the browser's manifest; a per-user one written by op would shadow it and go
# stale whenever op moves.
@test "op no longer writes a per-user browser manifest" {
  ! grep -q 'NativeMessagingHosts' "$OP" || return 1
  run "$OP" help
  [[ "$output" != *"browser connect"* ]] || return 1
}
