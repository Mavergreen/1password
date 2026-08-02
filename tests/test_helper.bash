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
  export ONEP_CLIP_CLEAR_SECS=1
  export DOCKER_HOST="tcp://192.0.2.1:2376"   # preset so op skips docker-machine
  # Don't let `op gui` spawn the REAL auto-recovery watcher: it's an infinite pgrep
  # loop, and a long-lived background child inherits bats's descriptors -> bats blocks
  # until it exits (never), hanging the suite. Tests that exercise the watcher opt back
  # in (unset this + point ONEP_RECOVER_WATCH at the fast stub).
  export ONEP_NO_RECOVER=1
  export ONEP_NO_LOCK_POLL=1     # don't spawn the infinite lock-state poll loop in tests
  export PATH="${BATS_TEST_DIRNAME}/stubs:$PATH"
  mkdir -p "$STUB_DIR"
  : > "$STUB_LOG"
}

teardown() {
  rm -rf "$WORK"
}
