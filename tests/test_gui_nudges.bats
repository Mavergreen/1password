#!/usr/bin/env bats
# op gui rebuild nudges: staleness (container age) + xpra protocol-compat.
# Both are advisory (non-fatal), rate-limited once/day via marker files, and unit-
# tested by sourcing op (OP_LIB=1) and driving the functions with stubs on PATH.

load test_helper

# A docker stub that answers `image inspect -f {{.Created}} <img>` with $DOCKER_CREATED
# and `exec <c> xpra --version` with $XPRA_VERSION_OUT. Put it first on PATH.
docker_stub() {
  mkdir -p "$WORK/dbin"
  cat > "$WORK/dbin/docker" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "image inspect") printf '%s\n' "${DOCKER_CREATED:-}"; exit 0 ;;
esac
# `docker exec <c> xpra --version`
for a in "$@"; do [ "$a" = "--version" ] && { printf '%s\n' "${XPRA_VERSION_OUT:-}"; exit 0; }; done
exit 0
EOF
  chmod +x "$WORK/dbin/docker"
  PATH="$WORK/dbin:$PATH"
}

@test "nudge_once prints the first time and is silent the same day" {
  OP_LIB=1 . "$OP"
  run nudge_once demo "hello rebuild"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"hello rebuild"* ]] || return 1
  # second call same process/day: marker exists -> silent
  run nudge_once demo "hello rebuild"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"hello rebuild"* ]] || return 1
}

@test "staleness: old image (definitely stale) nudges to rebuild" {
  docker_stub
  export DOCKER_CREATED="2000-01-01T00:00:00.000000000Z"
  OP_LIB=1 . "$OP"
  run check_container_staleness
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"rebuild"* ]] || return 1
  [[ "$output" == *"op setup --rebuild"* ]] || return 1
}

@test "staleness: fresh image does not nudge" {
  docker_stub
  export DOCKER_CREATED="2999-01-01T00:00:00.000000000Z"
  OP_LIB=1 . "$OP"
  run check_container_staleness
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"rebuild"* ]] || return 1
}

@test "staleness: unparseable created date is silent (never breaks gui)" {
  docker_stub
  export DOCKER_CREATED="not-a-date"
  OP_LIB=1 . "$OP"
  run check_container_staleness
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"rebuild"* ]] || return 1
}

@test "staleness honors ONEP_STALE_DAYS threshold" {
  docker_stub
  export DOCKER_CREATED="2000-01-01T00:00:00.000000000Z"
  export ONEP_STALE_DAYS=999999
  OP_LIB=1 . "$OP"
  run check_container_staleness
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"rebuild"* ]] || return 1
}

@test "xpra compat: matching major.minor is silent" {
  docker_stub
  export XPRA_VERSION_OUT="xpra v6.5.2-r0"
  OP_LIB=1 . "$OP"
  run check_xpra_compat
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"rebuild"* ]] || return 1
}

@test "xpra compat: different major.minor nudges to rebuild" {
  docker_stub
  export XPRA_VERSION_OUT="xpra v6.4.4-r0"
  OP_LIB=1 . "$OP"
  run check_xpra_compat
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"rebuild"* ]] || return 1
  [[ "$output" == *"op setup --rebuild"* ]] || return 1
}

@test "xpra compat: unreadable version is silent (never breaks gui)" {
  docker_stub
  export XPRA_VERSION_OUT=""
  OP_LIB=1 . "$OP"
  run check_xpra_compat
  [ "$status" -eq 0 ] || return 1
  [[ "$output" != *"rebuild"* ]] || return 1
}

@test "op gui emits a staleness nudge for an old container (integration)" {
  # Drive real `op gui` with stubs; force an old image + matching xpra so only the
  # staleness nudge fires. DOCKER_HOST is preset by the helper (preflight bypass).
  mkdir -p "$WORK/dbin"
  cat > "$WORK/dbin/docker" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "container inspect") echo true; exit 0 ;;       # State.Running -> true
  "image inspect") echo "2000-01-01T00:00:00.000000000Z"; exit 0 ;;
esac
for a in "$@"; do [ "$a" = "--version" ] && { echo "xpra v6.5.2-r0"; exit 0; }; done
exit 0
EOF
  chmod +x "$WORK/dbin/docker"
  PATH="$WORK/dbin:$PATH"
  # We assert on the nudge output, not $status: the stubbed gui flow doesn't run a
  # real viewer to completion, so only the nudge is a reliable signal here.
  run "$OP" gui
  [[ "$output" == *"days old"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"op setup --rebuild"* ]] || return 1
}
