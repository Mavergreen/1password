#!/usr/bin/env bats
# Milestone 3: the generator must reproduce 1Password's ACTIVE container behavior
# (the hard case) from apps/1password.conf -- printing/CUPS, ambient CAP_SYS_PTRACE,
# app-created group, browser allowlist, CLI-support pkgs -- while SHEDDING the VNC
# legacy. Generates into a throwaway dir so it never touches the repo tree.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  # Porthole renders the recipe now; this is a cross-repo integration check that 1password.conf
  # produces the right container. Needs the porthole engine as a sibling -- skip when absent (CI).
  GV="${PORTHOLE_DIR:-$ROOT/../mavericks-porthole}/bin/generate-viewer"
  [ -x "$GV" ] || skip "porthole engine not available as a sibling (generate-viewer)"
  GEN="$(mktemp -d "${TMPDIR:-/tmp}/gen1p.XXXXXX")"
  ( cd "$ROOT" && "$GV" 1password.conf --out "$GEN" ) >/dev/null
  DF="$GEN/1password/Dockerfile"
  ENTRY="$GEN/1password/start-1password-gui.sh"
  CHILD="$GEN/1password/1password-child.sh"
}

teardown() { rm -rf "$GEN"; }

@test "1Password Dockerfile installs 1password from AgileBits' apt repo, on the shared base" {
  grep -q 'FROM ghcr.io/modernmavericks/porthole-base' "$DF" || return 1   # xpra/Xvfb runtime is in the base
  grep -q 'downloads.1password.com/linux' "$DF" || return 1
  grep -qE 'apt-get install -y --no-install-recommends 1password 1password-cli' "$DF" || return 1
}

@test "1Password sheds the entire VNC/openbox legacy stack" {
  # packages
  ! grep -qiE 'tigervnc|x11vnc|xbindkeys|autocutsel|openbox' "$DF" || return 1
  # the legacy entrypoints/config are not COPYd in
  ! grep -qE 'start-op-xpra\.sh|start-gui\.sh|openbox-rc\.xml' "$DF" || return 1
}

@test "1Password Dockerfile has the printing (CUPS) slot: cups pkgs + lpadmin + ACL fix" {
  grep -q 'cups python3-cups' "$DF" || return 1
  grep -q 'usermod -aG lpadmin onepassword' "$DF" || return 1
  grep -q "sed -i 's|-u allow:\[\^ \]\*|-u allow:all|'" "$DF" || return 1
}

@test "1Password Dockerfile creates the app user in its package's onepassword group" {
  grep -q 'useradd -m -u 1000 -g onepassword onepassword' "$DF" || return 1
}

@test "1Password Dockerfile installs the op-CLI support packages (socat is in the base)" {
  grep -qE 'xdotool wmctrl x11-utils' "$DF" || return 1   # socat moved to the shared base
}

@test "1Password Dockerfile writes the browser-support allowlist (EXTRA_SETUP)" {
  grep -q '/etc/1password/custom_allowed_browsers' "$DF" || return 1
  grep -q "printf 'socat\\\\nsocat1\\\\n'" "$DF" || return 1
}

@test "1Password entrypoint keeps ambient CAP_SYS_PTRACE via setpriv" {
  sh -n "$ENTRY" || return 1
  grep -q -- '--inh-caps +sys_ptrace --ambient-caps +sys_ptrace' "$ENTRY" || return 1
}

@test "1Password entrypoint runs cupsd before xpra and enables printing" {
  grep -q '/usr/sbin/cupsd' "$ENTRY" || return 1
  grep -q 'lpstat -r' "$ENTRY" || return 1
  grep -q -- '--printing=yes' "$ENTRY" || return 1
}

@test "1Password entrypoint serves xpra :100 with the rgb,jpeg encodings on the volume" {
  grep -q 'xpra start' "$ENTRY" || return 1
  grep -q -- '--encodings=rgb,jpeg' "$ENTRY" || return 1
  grep -q 'OP_HOME=/home/onepassword' "$ENTRY" || return 1
}

@test "1Password child sets up the keyring, forces dark GTK, and execs 1password" {
  sh -n "$CHILD" || return 1
  grep -q 'gnome-keyring-daemon --unlock' "$CHILD" || return 1
  grep -q 'GTK_THEME=' "$CHILD" || return 1
  grep -q 'exec 1password --disable-gpu --user-data-dir=' "$CHILD" || return 1
}

@test "container spec fully provisions the ONE shared container: SYS_PTRACE + the op CLI-config volume" {
  # The whole point of the companion-CLI fix: the GUI and `op` CLI share a single container that
  # carries what BOTH need. PTRACE=yes must reach docker run as a --cap-add (via CAPS), and the op
  # CLI-config volume must be declared -- both resolved into the spec Porthole's `up` reads.
  spec="$GEN/1password.container"
  [ -f "$spec" ] || { echo "no spec at $spec"; return 1; }
  grep -q "CONTAINER='1password-gui'" "$spec" || return 1
  grep -q "CAPS='SYS_PTRACE'" "$spec" || return 1
  grep -q "EXTRA_VOLUMES='1password-cli-config:/root/.config/op'" "$spec" || return 1
}
