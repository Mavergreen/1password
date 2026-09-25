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
  [[ "$log" == *"exec -i -u onepassword -e HOME=/home/onepassword -e XDG_RUNTIME_DIR=/run/user/1000 1password-gui op vault list"* ]] || return 1
}

@test "interactive mode uses tty exec" {
  echo 'vaults here' > "$STUB_DIR/docker.stdout"
  run env ONEP_INTERACTIVE=1 "$OP" vault list
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"vaults here"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"exec -it -u onepassword -e HOME=/home/onepassword -e XDG_RUNTIME_DIR=/run/user/1000 1password-gui op vault list"* ]] || return 1
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

@test "missing container suggests setup" {
  echo 'Error: No such container: 1password-gui' > "$STUB_DIR/docker.stderr"
  echo 1 > "$STUB_DIR/docker.exit"
  run "$OP" op whoami
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"op setup"* ]] || return 1
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

# The CLI goes through the desktop app (Settings > Developer > Integrate with 1Password CLI): it runs
# as the app's user, the app's unlock is its sign-in, and locking the app locks it. So op never
# passes a session of its own, even if an old session file is lying around.
@test "the CLI runs as the app's user and never passes a session of its own" {
  mkdir -p "$ONEP_CONFIG_DIR"; echo 'STALE' > "$ONEP_CONFIG_DIR/session"
  run "$OP" op whoami
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"exec -i -u onepassword -e HOME=/home/onepassword -e XDG_RUNTIME_DIR=/run/user/1000 1password-gui op whoami"* ]] || { echo "$log"; return 1; }
  [[ "$log" != *"--session"* ]] || return 1
}

@test "signin and signout pass straight through to the CLI" {
  run "$OP" signin
  run "$OP" signout
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"1password-gui op signin"* ]] || return 1
  [[ "$log" == *"1password-gui op signout"* ]] || return 1
}

@test "a locked app or a dismissed prompt says how to unlock or approve" {
  echo '[ERROR] 2026/09/24 19:10:00 error initializing client: authorization prompt dismissed, please try again' > "$STUB_DIR/docker.stderr"
  echo 1 > "$STUB_DIR/docker.exit"
  run "$OP" vault list
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"op unlock"* ]] || return 1
  [[ "$output" == *"op approve"* ]] || return 1
}

# whoami (and anything else that only reads state) never prompts, so the hint must name a command that does.
@test "not signed in says to run op signin, which asks the app" {
  echo '[ERROR] 2026/09/24 22:29:15 account is not signed in' > "$STUB_DIR/docker.stderr"
  echo 1 > "$STUB_DIR/docker.exit"
  run "$OP" whoami
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"op signin"* ]] || return 1
}
