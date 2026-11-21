#!/usr/bin/env bats
# platform: host-agnostic
# Linux 1Password behaves like a Mac app through Porthole: the preset declares what differs, and the
# package's two small programs hand off to Porthole's engine tools.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/1p-native.XXXXXX")"
}
teardown() { rm -rf "$WORK"; }

conf() { ( . "$REPO/1password.conf"; eval "printf '%s' \"\$$1\"" ); }

@test "op is 1Password's own CLI, run in the app's container" {
  [ "$(conf CLI)" = op ]
  [ "$(conf CLI_op)" = /usr/bin/op ]
}

@test "the SSH agent socket follows the app's own setting, at the path ssh users already have" {
  [ "$(conf SOCKETS)" = ssh-agent ]
  [ "$(conf SOCKET_ssh_agent)" = '/home/onepassword/.1password/agent.sock ~/.1password/agent.sock' ]
}

# The schemes 1Password's own Linux package registers: its 1password.desktop has
#   MimeType=x-scheme-handler/onepassword;x-scheme-handler/onepassword8;
@test "the app takes the URL schemes 1Password's Linux package registers" {
  [ "$(conf URL_SCHEMES)" = 'onepassword onepassword8' ]
}

@test "the browser host runs 1Password's helper, with the user's and the pre-seeded browsers allowed" {
  [ "$(conf NATIVE_HOSTS)" = browser ]
  [ "$(conf NATIVE_HOST_browser)" = '/opt/1Password/1Password-BrowserSupport 1000:0' ]
  [ "$(conf NATIVE_HOST_browser_FILE)" = '/etc/1password/custom_allowed_browsers /usr/local/mavergreen/1password/share/1password/preseeded_browsers /etc/1password/custom_allowed_browsers' ]
  printf 'Momiji.app\nMomiji-Stable.app\nMomiji-Rolling.app\nPowerFox.app\nChromium.app\nSafari.app\n' \
    | diff -u - <(grep -v '^#' "$REPO/packaging/macos/preseeded_browsers")
}

# Each runs with a bare PATH (a browser starts its host that way), so neither looks on the PATH.
stub_engine() {
  e="$WORK/engine"; mkdir -p "$e"
  for t in porthole-cli porthole-native-host; do
    printf '#!/bin/sh\nprintf "%%s|" %s "$@" > "%s/argv"\n' "$t" "$WORK" > "$e/$t"; chmod +x "$e/$t"
  done
}

@test "op hands every argument to Porthole's porthole-cli, as given" {
  stub_engine
  run env -i PATH=/usr/bin:/bin PORTHOLE_ENGINE_BIN="$WORK/engine" "$REPO/bin/op" item get 'a b' '$x'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$WORK/argv")" = 'porthole-cli|1password|op|item|get|a b|$x|' ]
}

@test "the browser bridge hands the browser's arguments to Porthole's porthole-native-host" {
  stub_engine
  run env -i PATH=/usr/bin:/bin PORTHOLE_ENGINE_BIN="$WORK/engine" "$REPO/packaging/macos/op-browser-bridge" /m.json '{ext}'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$WORK/argv")" = 'porthole-native-host|1password|browser|/m.json|{ext}|' ]
}

@test "both use the installed Porthole's engine by default" {
  grep -q 'PORTHOLE_ENGINE_BIN:-/Applications/Porthole.app/Contents/Resources/engine/bin' "$REPO/bin/op"
  grep -q 'PORTHOLE_ENGINE_BIN:-/Applications/Porthole.app/Contents/Resources/engine/bin' "$REPO/packaging/macos/op-browser-bridge"
}
