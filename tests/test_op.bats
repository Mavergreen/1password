#!/usr/bin/env bats
# op gui: container setup/migration and Screen Sharing.

load test_helper

# NOTE: the container recipe (start-1password-gui.sh, Dockerfile, child) is no longer this repo's
# artifact -- Porthole renders it from templates/ at materialize time. Its content is covered by
# Porthole's own template tests + test_1password.bats (which generates the recipe from the conf).

@test "fresh setup builds image, creates container, prompts account add" {
  # 1 image inspect (absent), 2 build, 3 vol op-config, 4 vol op-gui-data,
  # 5 container inspect op-gui (absent), 6 run, 7 chmod, 8 container inspect
  # op-cli (absent), 9 account list (empty), 10 account add
  echo 1 > "$STUB_DIR/docker.exit.1"
  echo 1 > "$STUB_DIR/docker.exit.5"
  echo 1 > "$STUB_DIR/docker.exit.8"
  echo '[]' > "$STUB_DIR/docker.stdout.9"
  run "$OP" setup
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"build -t mavericks-1password"* ]] || return 1
  [[ "$log" == *"volume create op-config"* ]] || return 1
  [[ "$log" == *"volume create op-gui-data"* ]] || return 1
  [[ "$log" == *"run -d --name op-gui --hostname mavericks-1password --restart unless-stopped --init --shm-size 512m --security-opt seccomp=unconfined --cap-add SYS_PTRACE -e GEOMETRY=1440x900x24 -v op-config:/root/.config/op -v op-gui-data:/home/onepassword/.config/1Password mavericks-1password"* ]] || return 1
  [[ "$log" != *"-p 5900"* ]] || return 1
  [[ "$log" == *"chmod 700 /root/.config/op"* ]] || return 1
  [[ "$log" == *"op-gui op account add"* ]] || return 1
  [[ "$output" == *"op signin"* ]] || return 1
}

@test "setup existing container and account" {
  # 1 image inspect ok, 2 vol, 3 vol, 4 container inspect op-gui ok, 5 start,
  # 6 chmod, 7 container inspect op-cli (absent), 8 account list (configured)
  echo 1 > "$STUB_DIR/docker.exit.7"
  printf '[{"url":"my.1password.com"}]\n' > "$STUB_DIR/docker.stdout.8"
  run "$OP" setup
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" != *" build "* ]] || return 1
  [[ "$log" == *"start op-gui"* ]] || return 1
  [[ "$log" != *"account add"* ]] || return 1
  [[ "$output" == *"already configured"* ]] || return 1
}

@test "setup rebuild forces fresh image and container" {
  # 1 build --no-cache --pull, 2 rm -f op-gui, 3 vol, 4 vol,
  # 5 container inspect op-gui (absent), 6 run, 7 chmod,
  # 8 container inspect op-cli (absent), 9 account list (configured)
  echo 1 > "$STUB_DIR/docker.exit.5"
  echo 1 > "$STUB_DIR/docker.exit.8"
  printf '[{"url":"x"}]\n' > "$STUB_DIR/docker.stdout.9"
  run "$OP" setup --rebuild
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"build --no-cache --pull -t mavericks-1password"* ]] || return 1
  [[ "$log" == *"rm -f op-gui"* ]] || return 1
}

@test "setup retires old op cli container" {
  # 1 image inspect ok, 2 vol, 3 vol, 4 container inspect op-gui ok, 5 start,
  # 6 chmod, 7 container inspect op-cli OK, 8 rm -f op-cli,
  # 9 account list (configured)
  printf '[{"url":"x"}]\n' > "$STUB_DIR/docker.stdout.9"
  run "$OP" setup
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"rm -f op-cli"* ]] || return 1
  [[ "$output" == *"Retired"* ]] || return 1
}

@test "op gui starts container when stopped" {
  echo 'false' > "$STUB_DIR/docker.stdout.1"   # running probe
  run "$OP" gui
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"start op-gui"* ]] || return 1
}

@test "op gui stop stops the container and tears down the tunnel" {
  mkdir -p "$WORK/config"
  echo 4242 > "$WORK/config/xpra-tunnel.pid"
  run "$OP" gui stop
  [ "$status" -eq 0 ] || return 1
  [[ "$(cat "$STUB_LOG")" == *"stop op-gui"* ]] || return 1
  [ ! -f "$WORK/config/xpra-tunnel.pid" ] || return 1
}

@test "op gui launches Porthole pointed at the xpra tunnel" {
  echo 'true' > "$STUB_DIR/docker.stdout.1"   # container running probe
  run "$OP" gui
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"socat UNIX-LISTEN:"*"1password-xpra.sock,fork,reuseaddr"* ]] || return 1
  [[ "$log" == *"open"*"--args"*"1password-xpra.sock"* ]] || return 1
  [[ "$output" == *"launched Porthole -> "*"1password-xpra.sock"* ]] || return 1
}

@test "op gui spawns the auto-recovery watcher" {
  echo 'true' > "$STUB_DIR/docker.stdout.1"
  # Opt back into watcher-spawning (the helper disables it by default), but via the
  # fast stub -- which exits immediately, so it can't hang bats like the real daemon.
  unset ONEP_NO_RECOVER
  export ONEP_RECOVER_WATCH="${BATS_TEST_DIRNAME}/stubs/porthole-recover-watch"
  run "$OP" gui
  [ "$status" -eq 0 ] || return 1
  [[ "$(cat "$STUB_LOG")" == *"porthole-recover-watch"* ]] || return 1
}

@test "gui_recover_watch points at the installed Porthole engine (ONEP_RECOVER_WATCH overrides)" {
  # The watcher ships inside the installed Porthole engine now (was resolved $0-relative to a sibling
  # porthole checkout). A fixed install path -- no symlink chasing.
  run bash -c 'OP_LIB=1 source "$0"; gui_recover_watch' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "/Applications/Porthole.app/Contents/Resources/engine/bin/porthole-recover-watch" ] || { echo "$output"; return 1; }
  run env ONEP_RECOVER_WATCH=/tmp/rw bash -c 'OP_LIB=1 source "$0"; gui_recover_watch' "$OP"
  [ "$output" = "/tmp/rw" ] || { echo "$output"; return 1; }
}

@test "op gui stop kills the watcher before stopping the container" {
  mkdir -p "$WORK/config"
  echo 4243 > "$WORK/config/xpra-watch.pid"
  run "$OP" gui stop
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/config/xpra-watch.pid" ] || return 1
}

@test "xpra_tunnel_running rejects a live pid whose socket is gone (self-heal)" {
  mkdir -p "$WORK/config"
  echo 4242 > "$WORK/config/xpra-tunnel.pid"
  : > "$STUB_DIR/socat.alive"                  # stub `ps` reports the recorded pid alive...
  # ...but the socket it should be serving does not exist -> the tunnel is NOT usable.
  # The old check trusted the pid alone and reused a dead tunnel (viewer couldn't connect).
  run env ONEP_XPRA_SOCK="$WORK/nope.sock" bash -c 'OP_LIB=1 source "$0"; xpra_tunnel_running && echo RUNNING || echo NOT_RUNNING' "$OP"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"NOT_RUNNING"* ]] || return 1
}

@test "_vm_ip extracts the host from DOCKER_HOST (sourced unit)" {
  run bash -c 'DOCKER_HOST=tcp://192.0.2.1:2376 OP_LIB=1 source "$0"; _vm_ip' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "192.0.2.1" ] || return 1
}

@test "load_docker_env prefers the mavericks docker context when present" {
  : > "$STUB_DIR/docker-context.mavericks"   # marker: the managed context exists
  run env DOCKER_HOST= bash -c 'OP_LIB=1 source "$0"; load_docker_env; echo "CTX=${DOCKER_CONTEXT:-}"' "$OP"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"CTX=mavericks"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"docker context inspect mavericks"* ]] || return 1
  [[ "$log" != *"docker-machine env"* ]] || return 1   # never touched the stale-prone snapshot
}

@test "load_docker_env falls back to docker-machine env with no context" {
  run env DOCKER_HOST= bash -c 'OP_LIB=1 source "$0"; load_docker_env; echo "HOST=${DOCKER_HOST:-}"' "$OP"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"HOST=tcp://192.0.2.99:2376"* ]] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"docker context inspect mavericks"* ]] || return 1
  [[ "$log" == *"docker-machine env default"* ]] || return 1
}

@test "signin scrubs pasted master password" {
  printf 'hunter2' | pbcopy
  echo 'TOKEN123' > "$STUB_DIR/docker.stdout"
  run bash -c 'printf "hunter2\n" | "$0" signin' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$CLIPBOARD_FILE")" = "" ] || return 1
  [[ "$output" == *"Cleared your master password"* ]] || return 1
}

@test "signin fails loudly when config dir unwritable" {
  _parent="$WORK/lockedparent"
  mkdir -p "$_parent"
  chmod 500 "$_parent"
  echo 'TOKEN123' > "$STUB_DIR/docker.stdout"
  run bash -c 'printf "hunter2\n" | ONEP_CONFIG_DIR="$1/1p" "$0" signin' "$OP" "$_parent"
  chmod 700 "$_parent"
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"cannot write"* ]] || return 1
  [[ "$output" != *"Signed in"* ]] || return 1
}

@test "lock sends the lock shortcut to the app" {
  run "$OP" lock
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"xdotool"* ]] || return 1
  [[ "$log" == *"key --clearmodifiers ctrl+shift+l"* ]] || return 1
  [[ "$output" == *"Locked"* ]] || return 1
}

@test "lock reports when the app can't be reached" {
  echo 1 > "$STUB_DIR/docker.exit.1"
  run "$OP" lock
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"could not reach"* ]] || return 1
}

@test "unlock types the master password and reports success" {
  echo 1 > "$STUB_DIR/docker.exit.3"   # verify: lock screen gone -> unlocked
  run bash -c 'printf "sekret\n" | "$0" unlock' "$OP"
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"type --clearmodifiers --file -"* ]] || return 1
  [[ "$output" == *"Unlocked"* ]] || return 1
}

@test "unlock is a no-op when already unlocked" {
  echo 1 > "$STUB_DIR/docker.exit.1"   # guard: no lock screen found
  run bash -c 'printf "sekret\n" | "$0" unlock' "$OP"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"Already unlocked"* ]] || return 1
  [[ "$(cat "$STUB_LOG")" != *"type --clearmodifiers"* ]] || return 1
}

@test "unlock refuses an empty password" {
  run bash -c 'printf "\n" | "$0" unlock' "$OP"
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"empty"* ]] || return 1
}

@test "approve types the master password into a pending prompt and reports success" {
  echo '20971578' > "$STUB_DIR/docker.stdout.1"   # guard: approval dialog present
  # call 3 (verify) has no stdout -> dialog gone -> success
  run bash -c 'printf "sekret\n" | "$0" approve' "$OP"
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"type --clearmodifiers --file -"* ]] || return 1
  [[ "$output" == *"Approved"* ]] || return 1
}

@test "approve is a no-op when no prompt is pending" {
  run bash -c 'printf "sekret\n" | "$0" approve' "$OP"   # guard returns empty
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"No pending approval"* ]] || return 1
  [[ "$(cat "$STUB_LOG")" != *"type --clearmodifiers"* ]] || return 1
}

@test "approve refuses an empty password" {
  echo '20971578' > "$STUB_DIR/docker.stdout.1"   # dialog present
  run bash -c 'printf "\n" | "$0" approve' "$OP"
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"empty"* ]] || return 1
}

@test "approve reports failure if the dialog is still up afterward" {
  echo '20971578' > "$STUB_DIR/docker.stdout.1"   # guard: present
  echo '20971578' > "$STUB_DIR/docker.stdout.3"   # verify: STILL present -> failed
  run bash -c 'printf "wrongpw\n" | "$0" approve' "$OP"
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"approval failed"* ]] || return 1
}

@test "approval_window echoes a pending dialog id (sourced unit)" {
  echo '20971578' > "$STUB_DIR/docker.stdout"
  run bash -c 'OP_LIB=1 source "$0"; approval_window' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "20971578" ] || return 1
}

@test "notify_approval bells and sends a Mac notification (sourced unit)" {
  run bash -c 'OP_LIB=1 source "$0"; notify_approval' "$OP"
  [ "$status" -eq 0 ] || return 1
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"osascript"* ]] || return 1
  [[ "$log" == *"op approve"* ]] || return 1
}

@test "watch install-launchd writes a plist and loads it" {
  run env HOME="$WORK" "$OP" watch install-launchd
  [ "$status" -eq 0 ] || return 1
  plist="$WORK/Library/LaunchAgents/dev.modernmavericks.op-watch.plist"
  [ -f "$plist" ] || return 1
  [[ "$(cat "$plist")" == *"dev.modernmavericks.op-watch"* ]] || return 1
  [[ "$(cat "$plist")" == *"<string>watch</string>"* ]] || return 1
  [[ "$(cat "$STUB_LOG")" == *"launchctl load"* ]] || return 1
}

@test "watch uninstall-launchd removes the plist" {
  mkdir -p "$WORK/Library/LaunchAgents"
  : > "$WORK/Library/LaunchAgents/dev.modernmavericks.op-watch.plist"
  run env HOME="$WORK" "$OP" watch uninstall-launchd
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/Library/LaunchAgents/dev.modernmavericks.op-watch.plist" ] || return 1
}

@test "setup resolves the container build dir when op is run via a relative path (./bin/op)" {
  # pwd -P (physical) to match gui_root's own `pwd -P`; on a symlinked/automounted
  # tree (this repo is on NFS) logical vs physical paths can diverge, which would
  # make the assertion flake under load. Compare physical to physical.
  repo="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  echo 1 > "$STUB_DIR/docker.exit.1"   # image absent -> the build path (gui_build_dir) runs
  run bash -c 'cd "$1" && ./bin/op setup' _ "$repo"
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"build -t mavericks-1password $repo/1password"* ]] || return 1
}
