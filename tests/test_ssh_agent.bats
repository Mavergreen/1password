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
  [ -f "$WORK/Library/LaunchAgents/dev.mavergreen.op-ssh-agent.plist" ] || return 1
  plist="$(cat "$WORK/Library/LaunchAgents/dev.mavergreen.op-ssh-agent.plist")"
  [[ "$plist" == *"dev.mavergreen.op-ssh-agent"* ]] || return 1
  [[ "$plist" == *"--foreground"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"launchctl load"* ]] || return 1
}

@test "ssh-agent uninstall-launchd removes plist" {
  mkdir -p "$WORK/Library/LaunchAgents"
  : > "$WORK/Library/LaunchAgents/dev.mavergreen.op-ssh-agent.plist"
  run env HOME="$WORK" "$OP" ssh-agent uninstall-launchd
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"launchctl unload"* ]] || return 1
  [ ! -f "$WORK/Library/LaunchAgents/dev.mavergreen.op-ssh-agent.plist" ] || return 1
}

# ONE-TIME MIGRATION off the ModernMavericks identity (flag day 2026-09-22): op moves its own
# pre-flag-day LaunchAgents on its next run. DELETABLE with bin/op's migrate_old_launchd_agents.
old_agent_plist() {  # $1 = old label, $2 = a ProgramArguments marker to prove they are carried over
  mkdir -p "$ONEP_LAUNCH_AGENTS_DIR"
  cat > "$ONEP_LAUNCH_AGENTS_DIR/$1.plist" <<XML
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array><string>/opt/custom/op</string><string>$2</string></array>
</dict></plist>
XML
}

@test "flag day: any op run re-registers the old ssh-agent + watch agents under the new labels" {
  old_agent_plist dev.modernmavericks.op-ssh-agent ssh-agent-marker
  old_agent_plist dev.modernmavericks.op-watch watch-marker
  run "$OP" help
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  for x in ssh-agent watch; do
    new="$ONEP_LAUNCH_AGENTS_DIR/dev.mavergreen.op-$x.plist"
    [ -f "$new" ] || { echo "no $new: the agent would silently stop running after the upgrade"; return 1; }
    grep -q "<string>dev.mavergreen.op-$x</string>" "$new" || { echo "new plist kept the old Label"; return 1; }
    ! grep -q modernmavericks "$new" || { echo "new plist still names the old identity"; return 1; }
    grep -q "<string>/opt/custom/op</string><string>$x-marker</string>" "$new" \
      || { echo "ProgramArguments not carried over verbatim: $(cat "$new")"; return 1; }
    [ ! -e "$ONEP_LAUNCH_AGENTS_DIR/dev.modernmavericks.op-$x.plist" ] \
      || { echo "old $x plist left behind: launchd would load it again at next login"; return 1; }
    # load the new job BEFORE removing the old one: when op runs AS the old job, the remove ends it
    grep -n . "$STUB_LOG" | grep "launchctl load $new" | cut -d: -f1 > "$WORK/l"
    grep -n . "$STUB_LOG" | grep "launchctl remove dev.modernmavericks.op-$x\$" | cut -d: -f1 > "$WORK/r"
    [ -s "$WORK/l" ] && [ -s "$WORK/r" ] || { echo "missing load/remove for $x: $(cat "$STUB_LOG")"; return 1; }
    [ "$(cat "$WORK/l")" -lt "$(cat "$WORK/r")" ] || { echo "old $x job removed before the new one was loaded"; return 1; }
  done
}

@test "flag day: an existing new-label agent is kept; only the old one is retired" {
  old_agent_plist dev.modernmavericks.op-ssh-agent old-marker
  mkdir -p "$ONEP_LAUNCH_AGENTS_DIR"; echo keep-me > "$ONEP_LAUNCH_AGENTS_DIR/dev.mavergreen.op-ssh-agent.plist"
  run "$OP" help
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$ONEP_LAUNCH_AGENTS_DIR/dev.mavergreen.op-ssh-agent.plist")" = keep-me ] \
    || { echo "overwrote an already-migrated agent"; return 1; }
  [ ! -e "$ONEP_LAUNCH_AGENTS_DIR/dev.modernmavericks.op-ssh-agent.plist" ] || return 1
  grep -q 'launchctl remove dev.modernmavericks.op-ssh-agent$' "$STUB_LOG" || return 1
  ! grep -q 'launchctl load' "$STUB_LOG" || { echo "reloaded an agent that was already migrated"; return 1; }
}

@test "flag day: with no old agents, op touches no launchd state (idempotent)" {
  run "$OP" help
  [ "$status" -eq 0 ] || return 1
  ! grep -q launchctl "$STUB_LOG" || { echo "launchctl called with nothing to migrate: $(cat "$STUB_LOG")"; return 1; }
}

@test "flag day: the migration keeps op's stdout clean (op runs inside \$(...) in scripts)" {
  old_agent_plist dev.modernmavericks.op-watch m
  mkdir -p "$WORK/noisy"
  printf '#!/bin/sh\necho NOISE\necho NOISE >&2\nexit 1\n' > "$WORK/noisy/launchctl"; chmod 755 "$WORK/noisy/launchctl"
  PATH="$WORK/noisy:$PATH" run "$OP" help
  [ "$status" -eq 0 ] || { echo "a failing launchctl failed op: $output"; return 1; }
  [[ "$output" != *NOISE* ]] || { echo "launchctl output leaked into op's output"; return 1; }
}
