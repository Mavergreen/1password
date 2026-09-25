#!/usr/bin/env bats
# platform: host-agnostic
# op lock-state poller: publishes "locked"/"unlocked" to LOCK_STATE_FILE (which the
# Porthole viewer polls to badge its menu-bar glyph). Unit-tested via OP_LIB sourcing.

load test_helper

@test "lock_state_write_once: Lock Screen present -> writes 'locked'" {
  OP_LIB=1 . "$OP"
  CONTAINER=1password-gui
  LOCK_STATE_FILE="$WORK/lockstate"
  # default docker stub exits 0 -> xdotool search "finds" the Lock Screen -> locked
  run lock_state_write_once
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$WORK/lockstate")" = locked ] || return 1
}

@test "lock_state_write_once: no Lock Screen -> writes 'unlocked'" {
  OP_LIB=1 . "$OP"
  CONTAINER=1password-gui
  LOCK_STATE_FILE="$WORK/lockstate"
  echo 1 > "$STUB_DIR/docker.exit"   # docker exec (xdotool search) non-zero -> not found
  run lock_state_write_once
  [ "$(cat "$WORK/lockstate")" = unlocked ] || return 1
}

@test "lock_state_write_once writes atomically (no leftover .tmp)" {
  OP_LIB=1 . "$OP"
  CONTAINER=1password-gui
  LOCK_STATE_FILE="$WORK/lockstate"
  run lock_state_write_once
  [ -f "$WORK/lockstate" ] || return 1
  [ ! -f "$WORK/lockstate.tmp" ] || return 1
}

@test "lock_poll_stop removes the pidfile and the state file" {
  OP_LIB=1 . "$OP"
  LOCK_POLL_PID="$WORK/lock-poll.pid"
  LOCK_STATE_FILE="$WORK/lockstate"
  echo 999999 > "$LOCK_POLL_PID"      # a pid that isn't ours
  echo locked > "$LOCK_STATE_FILE"
  run lock_poll_stop
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/lock-poll.pid" ] || return 1
  [ ! -f "$WORK/lockstate" ] || return 1
}

@test "op gui does not spawn the poller when ONEP_NO_LOCK_POLL is set (default in tests)" {
  echo 'true' > "$STUB_DIR/docker.stdout.1"   # container running probe
  export ONEP_XPRA_SOCK="$WORK/1password-xpra.sock"
  run "$OP" gui
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -f "$WORK/config/lock-poll.pid" ] || return 1
}
