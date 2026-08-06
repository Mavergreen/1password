#!/usr/bin/env bats
# op ssh-agent: bridge command (unit), listener lifecycle, launchd.

load test_helper

@test "ssh-agent start launches the s6-ipcserver listener owner-only (-a 0600)" {
  echo 'true' > "$STUB_DIR/docker.stdout"
  run "$OP" ssh-agent start
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  # Mac-side transport is s6-ipcserver, owner-only; no socat UNIX-LISTEN / escaped-colon hack.
  [[ "$log" == *"s6-ipcserver -a 0600 "* ]] || return 1
  # It runs the container-side socat bridge as plain argv (the container's own socat, no backslash).
  [[ "$log" == *"docker exec -i 1password-gui socat STDIO UNIX-CONNECT:/home/onepassword/.1password/agent.sock"* ]] || return 1
  [[ "$log" != *"UNIX-LISTEN"* ]] || return 1
  [[ "$output" == *"export SSH_AUTH_SOCK="* ]] || return 1
}

@test "ssh-agent start is idempotent" {
  echo 'true' > "$STUB_DIR/docker.stdout"
  touch "$STUB_DIR/agent.alive"
  mkdir -p "$ONEP_CONFIG_DIR"
  echo 4242 > "$ONEP_CONFIG_DIR/ssh-agent.pid"
  run "$OP" ssh-agent start
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" != *"s6-ipcserver"* ]] || return 1
  [[ "$output" == *"already running"* ]] || return 1
}

@test "ssh-agent start warns when remote socket absent" {
  echo 1 > "$STUB_DIR/docker.exit"
  run "$OP" ssh-agent start
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"Use the SSH agent"* ]] || return 1
}

@test "ssh-agent stop terminates the recorded process and cleans up" {
  mkdir -p "$ONEP_CONFIG_DIR"
  sleep 30 & _p=$!
  echo "$_p" > "$ONEP_CONFIG_DIR/ssh-agent.pid"
  : > "$WORK/agent.sock"
  run "$OP" ssh-agent stop
  [ "$status" -eq 0 ] || return 1
  ! kill -0 "$_p" 2>/dev/null || return 1
  [ ! -f "$ONEP_CONFIG_DIR/ssh-agent.pid" ] || return 1
}

@test "ssh-agent status running" {
  mkdir -p "$ONEP_CONFIG_DIR"
  echo 4242 > "$ONEP_CONFIG_DIR/ssh-agent.pid"
  touch "$STUB_DIR/agent.alive"
  run "$OP" ssh-agent status
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"running"* ]] || return 1
}

@test "ssh-agent status stopped" {
  run "$OP" ssh-agent status
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"not running"* ]] || return 1
}

@test "ssh-agent install-launchd writes a plist and loads it" {
  run env HOME="$WORK" "$OP" ssh-agent install-launchd
  [ "$status" -eq 0 ] || return 1
  [ -f "$WORK/Library/LaunchAgents/dev.modernmavericks.op-ssh-agent.plist" ] || return 1
  plist="$(cat "$WORK/Library/LaunchAgents/dev.modernmavericks.op-ssh-agent.plist")"
  [[ "$plist" == *"dev.modernmavericks.op-ssh-agent"* ]] || return 1
  [[ "$plist" == *"--foreground"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"launchctl load"* ]] || return 1
}

@test "ssh-agent uninstall-launchd removes plist" {
  mkdir -p "$WORK/Library/LaunchAgents"
  : > "$WORK/Library/LaunchAgents/dev.modernmavericks.op-ssh-agent.plist"
  run env HOME="$WORK" "$OP" ssh-agent uninstall-launchd
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"launchctl unload"* ]] || return 1
  [ ! -f "$WORK/Library/LaunchAgents/dev.modernmavericks.op-ssh-agent.plist" ] || return 1
}
