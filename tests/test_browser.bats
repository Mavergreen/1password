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
  grep -q 'mv -f "$t" /etc/1password/custom_allowed_browsers$' "$STUB_LOG"
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

@test "two browsers connecting at once both write the allowlist" {
  run "$OP" _browser-bridge '{id}' </dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  d="$BATS_TEST_TMPDIR/etc1p"; mkdir -p "$d"
  sed "s#/etc/1password#$d#g" "$STUB_DIR/allowlist.sh" > "$BATS_TEST_TMPDIR/w.sh"
  i=0; : > "$BATS_TEST_TMPDIR/fails"
  while [ $i -lt 30 ]; do
    (yes A.app | head -2000 | sh "$BATS_TEST_TMPDIR/w.sh" 2>/dev/null || echo f >> "$BATS_TEST_TMPDIR/fails") &
    (yes B.app | head -2000 | sh "$BATS_TEST_TMPDIR/w.sh" 2>/dev/null || echo f >> "$BATS_TEST_TMPDIR/fails") &
    wait; i=$((i + 1))
  done
  [ ! -s "$BATS_TEST_TMPDIR/fails" ] || { echo "$(wc -l < "$BATS_TEST_TMPDIR/fails") writes failed"; return 1; }
  [ "$(wc -l < "$d/custom_allowed_browsers")" -eq 2000 ]
}

@test "the trust check is of the file read, not a symlink to it" {
  f="$BATS_TEST_TMPDIR/allowed"; printf 'Evil.app\n' > "$f"
  # a root-owned link (what plain stat sees) to a user-writable file (what stat -L sees)
  mkdir -p "$BATS_TEST_TMPDIR/s"
  printf '#!/bin/sh\ncase "$1" in -L) echo "501 666" ;; *) echo "0 755" ;; esac\n' > "$BATS_TEST_TMPDIR/s/stat"
  chmod +x "$BATS_TEST_TMPDIR/s/stat"
  PATH="$BATS_TEST_TMPDIR/s:$PATH" ONEP_MAC_BROWSER_ALLOWLIST="$f" run "$OP" _browser-bridge '{id}' </dev/null
  [ -f "$STUB_DIR/allowlist.in" ] || return 1
  ! grep -q Evil.app "$STUB_DIR/allowlist.in"
}

@test "with no Porthole engine at all, nothing is run from the browser's working directory" {
  b="$BATS_TEST_TMPDIR/nos6"; mkdir -p "$b"
  for t in "${BATS_TEST_DIRNAME}"/stubs/*; do [ "${t##*/}" = s6-ipcserver ] || ln -s "$t" "$b/"; done
  w="$BATS_TEST_TMPDIR/cwd"; mkdir -p "$w"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$w" > "$w/porthole-standin-run"; chmod +x "$w/porthole-standin-run"
  cd "$w"
  PATH="$b:/usr/bin:/bin" ONEP_PORTHOLE_BIN=/nonexistent/porthole run "$OP" _browser-bridge '{id}' </dev/null
  [ "$status" -ne 0 ] || return 1
  [ ! -e "$w/ran" ] || return 1
  [[ "$output" == *"reinstall Porthole"* ]] || { echo "$output"; return 1; }
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
