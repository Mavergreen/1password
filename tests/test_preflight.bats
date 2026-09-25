#!/usr/bin/env bats
# platform: host-agnostic
# op host preflight: Container Tools -> Fusion checks via `docker-machine-ctl status`.
# preflight_host reuses Container Tools' status contract. We source op as a library
# (OP_LIB=1) and drive the function directly with a stubbed ctl on a controlled PATH.

load test_helper

# Put a docker-machine-ctl stub that echoes $1 for `status` first on PATH, and
# clear the explicit-endpoint bypass so preflight actually runs.
ctl_returns() {   # $1 = status word to emit
  mkdir -p "$WORK/ctlbin"
  cat > "$WORK/ctlbin/docker-machine-ctl" <<EOF
#!/bin/sh
[ "\$1" = status ] && printf '%s\n' "$1"
EOF
  chmod +x "$WORK/ctlbin/docker-machine-ctl"
  PATH="$WORK/ctlbin:$PATH"
  unset DOCKER_HOST DOCKER_CONTEXT
}

@test "preflight passes when Container Tools reports running" {
  ctl_returns running
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "preflight: no Fusion -> actionable VMware Fusion error" {
  ctl_returns no-fusion
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"VMware Fusion"* ]] || return 1
}

@test "preflight: VM absent -> points at docker-machine-ctl setup" {
  ctl_returns absent
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"docker-machine-ctl setup"* ]] || return 1
}

@test "preflight: VM stopped -> points at docker-machine-ctl start" {
  ctl_returns stopped
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"docker-machine-ctl start"* ]] || return 1
}

@test "preflight: creating -> busy, try again" {
  ctl_returns creating
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"try again"* ]] || return 1
}

@test "preflight: working:<op> -> busy with the op name" {
  ctl_returns "working:restart"
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"restart"* ]] || return 1
  [[ "$output" == *"try again"* ]] || return 1
}

@test "preflight: unknown/error word -> generic actionable error" {
  ctl_returns error
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"docker-machine-ctl status"* ]] || return 1
}

@test "preflight: Container Tools not installed -> install hint" {
  unset DOCKER_HOST DOCKER_CONTEXT
  PATH="/usr/bin:/bin"   # no docker-machine-ctl anywhere
  export ONEP_TOOLS_DIR="$WORK/empty"; mkdir -p "$ONEP_TOOLS_DIR"
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"Container Tools"* ]] || return 1
}

@test "preflight is skipped when DOCKER_HOST is explicit (even with ctl absent)" {
  export DOCKER_HOST="tcp://192.0.2.1:2376"
  PATH="/usr/bin:/bin"
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "preflight is skipped when DOCKER_CONTEXT is explicit" {
  unset DOCKER_HOST
  export DOCKER_CONTEXT="mavericks"
  PATH="/usr/bin:/bin"
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "preflight honors ONEP_SKIP_PREFLIGHT" {
  unset DOCKER_HOST DOCKER_CONTEXT
  export ONEP_SKIP_PREFLIGHT=1
  PATH="/usr/bin:/bin"
  OP_LIB=1 . "$OP"
  run preflight_host
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "load_docker_env runs preflight (no-fusion blocks before Docker is used)" {
  ctl_returns no-fusion
  OP_LIB=1 . "$OP"
  run load_docker_env
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"VMware Fusion"* ]] || return 1
}
