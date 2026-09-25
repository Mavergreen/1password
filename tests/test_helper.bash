# platform: host-agnostic
# Shared BATS setup for the op suite. `load test_helper` from each .bats file.
# Each @test gets a fresh temp workspace with stub docker/pbcopy/etc. on PATH.

OP="${BATS_TEST_DIRNAME}/../bin/op"

setup() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/op-bats.XXXXXX")"
  export STUB_DIR="$WORK/stub"
  export STUB_LOG="$STUB_DIR/log"
  export CLIPBOARD_FILE="$WORK/clipboard"
  export ONEP_CONFIG_DIR="$WORK/config"
  export ONEP_SSH_AUTH_SOCK="$WORK/agent.sock"
  # Never let op's LaunchAgent handling touch the real ~/Library.
  export ONEP_LAUNCH_AGENTS_DIR="$WORK/Library/LaunchAgents"
  export ONEP_CLIP_CLEAR_SECS=1
  export DOCKER_HOST="tcp://192.0.2.1:2376"   # preset so op skips docker-machine
  # Don't let `op gui` spawn the REAL auto-recovery watcher: it's an infinite pgrep
  # loop, and a long-lived background child inherits bats's descriptors -> bats blocks
  # until it exits (never), hanging the suite. Tests that exercise the watcher opt back
  # in (unset this + point ONEP_RECOVER_WATCH at the fast stub).
  export ONEP_NO_RECOVER=1
  export ONEP_NO_LOCK_POLL=1     # don't spawn the infinite lock-state poll loop in tests
  # op gui now delegates to the materialized "Linux 1Password.app"; point it at a temp bundle that
  # exists so cmd_gui proceeds (the real one is dropped by the preset's postinstall + materialize).
  export ONEP_GUI_APP="$WORK/Linux 1Password.app"
  mkdir -p "$ONEP_GUI_APP/Contents/Resources"
  # Porthole's resolved container spec (materialize drops this into the app). op reads the container
  # NAME from it -- it no longer owns/names the container -- so resolve_container finds 1password-gui.
  cat > "$ONEP_GUI_APP/Contents/Resources/1password.container" <<'SPEC'
NAME='Linux 1Password'
CONTAINER='1password-gui'
IMAGE='mavericks-1password'
DATADIR='/home/onepassword/.config/1Password'
VOLUME='1password-gui-data'
CAPS='SYS_PTRACE'
EXTRA_VOLUMES='1password-cli-config:/root/.config/op'
HOST_MOUNTS=''
SPEC
  # op setup delegates container creation to `porthole up`; point at the logging stub, not the
  # real engine (which would try to docker build). porthole_bin() honors ONEP_PORTHOLE_BIN.
  export ONEP_PORTHOLE_BIN="${BATS_TEST_DIRNAME}/stubs/porthole"
  export PATH="${BATS_TEST_DIRNAME}/stubs:$PATH"
  mkdir -p "$STUB_DIR"
  : > "$STUB_LOG"
}

teardown() {
  rm -rf "$WORK"
}
