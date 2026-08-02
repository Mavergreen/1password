#!/usr/bin/env bats
# op CLI: dispatch, docker-env, session, clipboard.

load test_helper

@test "usage when no args" {
  run "$OP"
  [ "$status" -eq 2 ] || return 1
  [[ "$output" == *"usage: op"* ]] || return 1
}

@test "unknown command passes through to op" {
  echo 'vaults here' > "$STUB_DIR/docker.stdout"
  run "$OP" vault list
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"exec -i op-gui op vault list"* ]] || return 1
}

@test "interactive mode uses tty exec" {
  echo 'vaults here' > "$STUB_DIR/docker.stdout"
  run env ONEP_INTERACTIVE=1 "$OP" vault list
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"vaults here"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"exec -it op-gui op vault list"* ]] || return 1
}

@test "interactive mode propagates exit code" {
  echo 'item not found' > "$STUB_DIR/docker.stderr"
  echo 3 > "$STUB_DIR/docker.exit"
  run env ONEP_INTERACTIVE=1 "$OP" item get nope
  [ "$status" -eq 3 ] || return 1
  [ "$output" = "item not found" ] || return 1
}

@test "non tty stays captured" {
  run "$OP" vault list
  log="$(cat "$STUB_LOG")"
  [[ "$log" != *" -it "* ]] || return 1
}

@test "help exits zero" {
  run "$OP" help
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"usage: op"* ]] || return 1
}

@test "docker env looked up when unset" {
  run env DOCKER_HOST= "$OP" op whoami
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"docker-machine env default"* ]] || return 1
  [[ "$(cat "$ONEP_CONFIG_DIR/docker-env")" == *'DOCKER_HOST="tcp://192.0.2.99:2376"'* ]] || return 1
}

@test "vm down gives actionable error" {
  echo 'Cannot connect to the Docker daemon at tcp://192.0.2.1:2376' > "$STUB_DIR/docker.stderr"
  echo 1 > "$STUB_DIR/docker.exit"
  run "$OP" op whoami
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"docker-machine start default"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"docker-machine env default"* ]] || return 1
}

@test "signin saves token with tight perms" {
  echo 'TOKEN123' > "$STUB_DIR/docker.stdout"
  run bash -c 'printf "hunter2\n" | "$0" signin' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$ONEP_CONFIG_DIR/session")" = "TOKEN123" ] || return 1
  [ "$(stat -f %Lp "$ONEP_CONFIG_DIR/session")" = "600" ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"exec -i op-gui op signin --raw"* ]] || return 1
}

@test "signin refuses empty password" {
  run bash -c 'printf "\n" | "$0" signin' "$OP"
  [ "$status" -eq 1 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" != *"op signin"* ]] || return 1
}

@test "signin leaves unrelated clipboard alone" {
  printf 'grocery list' | pbcopy
  echo 'TOKEN123' > "$STUB_DIR/docker.stdout"
  run bash -c 'printf "hunter2\n" | "$0" signin' "$OP"
  [ "$(cat "$CLIPBOARD_FILE")" = "grocery list" ] || return 1
}


@test "signout clears session" {
  mkdir -p "$ONEP_CONFIG_DIR"
  echo 'TOK' > "$ONEP_CONFIG_DIR/session"
  run "$OP" signout
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$ONEP_CONFIG_DIR/session" ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"op signout --session TOK"* ]] || return 1
}

@test "session flag appended when cached" {
  mkdir -p "$ONEP_CONFIG_DIR"
  echo 'TOK' > "$ONEP_CONFIG_DIR/session"
  run "$OP" op whoami
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"op whoami --session TOK"* ]] || return 1
}

@test "no session flag without cache" {
  run "$OP" op whoami
  log="$(cat "$STUB_LOG")"
  [[ "$log" != *" --session"* ]] || return 1
}

@test "expired session triggers resignin and retry" {
  mkdir -p "$ONEP_CONFIG_DIR"
  echo 'OLDTOK' > "$ONEP_CONFIG_DIR/session"
  echo '[ERROR] 2026/07/07 session expired, sign in to create a new session' > "$STUB_DIR/docker.stderr.1"
  echo 1 > "$STUB_DIR/docker.exit.1"
  echo 'NEWTOK' > "$STUB_DIR/docker.stdout.2"
  echo 'amitai@example.com' > "$STUB_DIR/docker.stdout.3"
  run bash -c 'printf "hunter2\n" | "$0" op whoami 2>/dev/null' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "amitai@example.com" ] || return 1
  [ "$(cat "$ONEP_CONFIG_DIR/session")" = "NEWTOK" ] || return 1
  [ "$(cat "$STUB_DIR/docker.calls")" = "3" ] || return 1
}

@test "missing container suggests setup" {
  echo 'Error: No such container: op-gui' > "$STUB_DIR/docker.stderr"
  echo 1 > "$STUB_DIR/docker.exit"
  run "$OP" op whoami
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"op setup"* ]] || return 1
}

@test "second auth error not retried again" {
  mkdir -p "$ONEP_CONFIG_DIR"
  echo 'OLDTOK' > "$ONEP_CONFIG_DIR/session"
  echo '[ERROR] session expired, sign in to create a new session' > "$STUB_DIR/docker.stderr.1"
  echo 1 > "$STUB_DIR/docker.exit.1"
  echo 'NEWTOK' > "$STUB_DIR/docker.stdout.2"
  echo '[ERROR] session expired, sign in to create a new session' > "$STUB_DIR/docker.stderr.3"
  echo 1 > "$STUB_DIR/docker.exit.3"
  run bash -c 'printf "hunter2\n" | "$0" op whoami' "$OP"
  [ "$status" -eq 1 ] || return 1
  [ "$(cat "$STUB_DIR/docker.calls")" = "3" ] || return 1
  [[ "$output" == *"session expired"* ]] || return 1
}

@test "copy puts password on clipboard" {
  echo 's3cret!' > "$STUB_DIR/docker.stdout"
  run "$OP" copy GitHub
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$CLIPBOARD_FILE")" = "s3cret!" ] || return 1
  [[ "$output" == *"auto-clears"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"op item get GitHub --fields password --reveal"* ]] || return 1
}

@test "copy autoclears unchanged clipboard" {
  echo 's3cret!' > "$STUB_DIR/docker.stdout"
  "$OP" copy GitHub >/dev/null 2>&1
  sleep 2
  [ "$(cat "$CLIPBOARD_FILE")" = "" ] || return 1
}

@test "copy leaves changed clipboard alone" {
  echo 's3cret!' > "$STUB_DIR/docker.stdout"
  "$OP" copy GitHub >/dev/null 2>&1
  printf 'something else' | pbcopy
  sleep 2
  [ "$(cat "$CLIPBOARD_FILE")" = "something else" ] || return 1
}

@test "copy errors when no password field" {
  : > "$STUB_DIR/docker.stdout"
  run "$OP" copy GitHub
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"no password field"* ]] || return 1
}

@test "otp errors when no otp field" {
  : > "$STUB_DIR/docker.stdout"
  run "$OP" otp GitHub
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"no one-time password"* ]] || return 1
}

@test "otp puts code on clipboard" {
  echo '123456' > "$STUB_DIR/docker.stdout"
  run "$OP" otp GitHub
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$CLIPBOARD_FILE")" = "123456" ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"op item get GitHub --otp"* ]] || return 1
}

@test "clip puts stdin on clipboard" {
  run bash -c 'printf "sekrit-value" | "$0" clip' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$CLIPBOARD_FILE")" = "sekrit-value" ] || return 1
  [[ "$output" == *"auto-clears"* ]] || return 1
}

@test "clip refuses empty stdin" {
  run bash -c 'printf "" | "$0" clip' "$OP"
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"nothing on stdin"* ]] || return 1
}
