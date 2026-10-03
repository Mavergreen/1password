#!/usr/bin/env bats
# platform: host-agnostic
# op _browser-bridge: the 1Password extension's native host, run through the package's bridge.

load test_helper

@test "browser_bridge_cmd runs the helper under container socat, pointed at the viewed instance (sourced unit)" {
  run bash -c 'OP_LIB=1 source "$0"; CONTAINER=1password-gui; browser_bridge_cmd' "$OP"
  [ "$status" -eq 0 ] || return 1
  # HOME/XDG_RUNTIME_DIR must match the Porthole/xpra instance the user unlocks, so
  # the extension reaches the unlocked app rather than the old VNC instance.
  [[ "$output" == *"docker exec -i -u 1000:0 -e HOME=/home/onepassword -e XDG_RUNTIME_DIR=/run/user/1000 1password-gui socat STDIO EXEC:/opt/1Password/1Password-BrowserSupport"* ]] || return 1
}

# Firefox passes the manifest path, then the extension id; the helper wants only the id.
@test "_browser-bridge hands the helper the extension id the browser passed last" {
  run "$OP" _browser-bridge /path/to/manifest.json '{d634138d-c276-4fc8-924b-40a0ea21d284}'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q 'docker exec -i -u 1000:0 .* 1password-gui socat STDIO EXEC:/opt/1Password/1Password-BrowserSupport {d634138d-c276-4fc8-924b-40a0ea21d284}$' "$STUB_LOG" || { cat "$STUB_LOG"; return 1; }
}

# The package installs the browser's manifest; a per-user one written by op would shadow it and go
# stale whenever op moves.
@test "op no longer writes a per-user browser manifest" {
  ! grep -q 'NativeMessagingHosts' "$OP" || return 1
  run "$OP" help
  [[ "$output" != *"browser connect"* ]] || return 1
}
