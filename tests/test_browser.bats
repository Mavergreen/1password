#!/usr/bin/env bats
# op browser: bridge command + manifest (unit), connect/disconnect.

load test_helper

@test "browser_bridge_cmd runs the helper under container socat, pointed at the viewed instance (sourced unit)" {
  run bash -c 'OP_LIB=1 source "$0"; CONTAINER=1password-gui; browser_bridge_cmd' "$OP"
  [ "$status" -eq 0 ] || return 1
  # HOME/XDG_RUNTIME_DIR must match the Porthole/xpra instance the user unlocks, so
  # the extension reaches the unlocked app rather than the old VNC instance.
  [[ "$output" == *"docker exec -i -u 1000:0 -e HOME=/home/onepassword -e XDG_RUNTIME_DIR=/run/user/1000 1password-gui socat STDIO EXEC:/opt/1Password/1Password-BrowserSupport"* ]] || return 1
}

@test "browser_manifest_json is a stdio manifest for the 1Password extension (sourced unit)" {
  # ONEP_CONFIG_DIR (exported by setup) makes BROWSER_LAUNCHER resolve to a real path
  run bash -c 'OP_LIB=1 source "$0"; browser_manifest_json' "$OP"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *'"name": "com.1password.1password"'* ]] || return 1
  [[ "$output" == *'"type": "stdio"'* ]] || return 1
  [[ "$output" == *'d634138d-c276-4fc8-924b-40a0ea21d284'* ]] || return 1
}

@test "browser connect writes the manifest and an argv-forwarding launcher" {
  m="$WORK/nmh/com.1password.1password.json"
  run env ONEP_BROWSER_MANIFEST="$m" "$OP" browser-connect
  [ "$status" -eq 0 ] || return 1
  [ -f "$m" ] || return 1
  j="$(cat "$m")"
  [[ "$j" == *'"name": "com.1password.1password"'* ]] || return 1
  [[ "$j" == *"op-browser-bridge"* ]] || return 1
  [[ "$j" == *'d634138d-c276-4fc8-924b-40a0ea21d284'* ]] || return 1
  [[ "$output" == *"restart"* ]] || return 1
}

# The launcher used to bake in the absolute path of whichever op wrote it; that checkout was later
# renamed, so every connection exec'd a missing file and the extension ran on its own, with its own
# lock state (2026-09-24). It must find op when the browser runs it: browsers start native hosts with
# a PATH that lacks /usr/local/bin, and whatever op is found gets the browser's argv unchanged.
@test "the browser launcher runs whichever op it finds at run time, with the browser's argv" {
  run env ONEP_BROWSER_MANIFEST="$WORK/nmh/m.json" "$OP" browser-connect
  [ "$status" -eq 0 ] || return 1
  ! grep -q "$(dirname "$OP")" "$ONEP_CONFIG_DIR/op-browser-bridge" || return 1
  mkdir -p "$WORK/fakebin"
  printf '#!/bin/sh\nprintf "%%s|" "$@" > "%s/op.argv"\n' "$WORK" > "$WORK/fakebin/op"
  chmod +x "$WORK/fakebin/op"
  PATH="$WORK/fakebin:/usr/bin:/bin" "$ONEP_CONFIG_DIR/op-browser-bridge" /path/to/manifest.json '{ext-id}'
  [ "$(cat "$WORK/op.argv")" = "_browser-bridge|/path/to/manifest.json|{ext-id}|" ]
}

# The Mac side bridges with docker exec; socat runs inside the container, not on the Mac.
@test "browser connect does not need socat on the Mac" {
  mkdir -p "$WORK/nosocat"
  for t in docker; do ln -s "${BATS_TEST_DIRNAME}/stubs/$t" "$WORK/nosocat/$t"; done
  run env PATH="$WORK/nosocat:/usr/bin:/bin" ONEP_TOOLS_DIR="$WORK/nosocat" \
      ONEP_BROWSER_MANIFEST="$WORK/nmh/m.json" "$OP" browser-connect
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "browser disconnect removes the manifest" {
  m="$WORK/nmh/com.1password.1password.json"
  mkdir -p "$WORK/nmh"; : > "$m"
  run env ONEP_BROWSER_MANIFEST="$m" "$OP" browser-disconnect
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$m" ] || return 1
}

@test "usage lists the browser command" {
  run "$OP" help
  [[ "$output" == *"browser"* ]] || return 1
}
