#!/usr/bin/env bats
# platform: host-agnostic
# op gui: container setup and Screen Sharing.

load test_helper

# NOTE: the container recipe (start-1password-gui.sh, Dockerfile, child) is no longer this repo's
# artifact -- Porthole renders it from templates/ at materialize time. Its content is covered by
# Porthole's own template tests + test_1password.bats (which generates the recipe from the conf).

# op no longer builds/runs/names its OWN container. Porthole is the single creator: `op setup`
# delegates to `porthole up <spec>` (the porthole stub logs it). Accounts belong to the app; the CLI
# reaches them through it, so setup only checks that it can.
@test "setup brings the container up via Porthole and adds no account of its own" {
  printf '[{"url":"my.1password.com"}]\n' > "$STUB_DIR/docker.stdout.1"
  run "$OP" setup
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  log="$(cat "$STUB_LOG")"
  [[ "$log" == *"porthole up "*"1password.container"* ]] || { echo "$log"; return 1; }
  [[ "$log" != *"docker build"* ]] || return 1
  [[ "$log" != *"run -d --name"* ]] || return 1
  [[ "$log" != *"account add"* ]] || return 1
  [[ "$log" != *"/root/.config/op"* ]] || return 1
  [[ "$log" == *"-u onepassword"*"1password-gui op account list"* ]] || return 1
}

@test "setup with no account visible says to sign in to the app and turn on CLI integration" {
  echo '[]' > "$STUB_DIR/docker.stdout.1"
  run "$OP" setup
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Integrate with 1Password CLI"* ]] || return 1
}
@test "setup --rebuild passes --rebuild through to porthole up" {
  printf '[{"url":"x"}]\n' > "$STUB_DIR/docker.stdout.1"
  run "$OP" setup --rebuild
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$(cat "$STUB_LOG")" == *"porthole up --rebuild "*"1password.container"* ]] || { cat "$STUB_LOG"; return 1; }
}

@test "op gui stop quits the viewer app and stops the container" {
  run "$OP" gui stop
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$(cat "$STUB_LOG")" == *"stop 1password-gui"* ]] || { cat "$STUB_LOG"; return 1; }   # container stopped
}

@test "op gui opens the materialized Linux 1Password.app (whose launcher owns the container + viewer)" {
  run "$OP" gui
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$(cat "$STUB_LOG")" == *"open"*"Linux 1Password.app"* ]] || { cat "$STUB_LOG"; return 1; }
  [[ "$output" == *"opened "*"Linux 1Password.app"* ]] || return 1
  # op no longer starts the container or runs docker itself for gui -- the app/launcher does
  [[ "$(cat "$STUB_LOG")" != *"docker start"* ]] || { cat "$STUB_LOG"; return 1; }
}

# op gui no longer runs the viewer OR its recovery watcher itself: the materialized "Linux
# 1Password.app" owns the xpra tunnel, viewer, and recovery (exercised by Porthole's launcher tests).
# The former "op gui spawns the watcher" / "gui stop kills the watcher" tests are retired accordingly.

@test "gui_recover_watch points at the installed Porthole engine (ONEP_RECOVER_WATCH overrides)" {
  # The watcher ships inside the installed Porthole engine now (was resolved $0-relative to a sibling
  # porthole checkout). A fixed install path -- no symlink chasing.
  run bash -c 'OP_LIB=1 source "$0"; gui_recover_watch' "$OP"
  [ "$status" -eq 0 ] || return 1
  [ "$output" = "/Applications/Porthole.app/Contents/Resources/engine/bin/porthole-recover-watch" ] || { echo "$output"; return 1; }
  run env ONEP_RECOVER_WATCH=/tmp/rw bash -c 'OP_LIB=1 source "$0"; gui_recover_watch' "$OP"
  [ "$output" = "/tmp/rw" ] || { echo "$output"; return 1; }
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
  plist="$WORK/Library/LaunchAgents/dev.mavergreen.op-watch.plist"
  [ -f "$plist" ] || return 1
  [[ "$(cat "$plist")" == *"dev.mavergreen.op-watch"* ]] || return 1
  [[ "$(cat "$plist")" == *"<string>watch</string>"* ]] || return 1
  [[ "$(cat "$STUB_LOG")" == *"launchctl load"* ]] || return 1
}

@test "watch uninstall-launchd removes the plist" {
  mkdir -p "$WORK/Library/LaunchAgents"
  : > "$WORK/Library/LaunchAgents/dev.mavergreen.op-watch.plist"
  run env HOME="$WORK" "$OP" watch uninstall-launchd
  [ "$status" -eq 0 ] || return 1
  [ ! -f "$WORK/Library/LaunchAgents/dev.mavergreen.op-watch.plist" ] || return 1
}

# (Retired: "setup resolves the container build dir via ./bin/op" -- op setup no longer builds a
# container; it delegates to `porthole up`. gui_root's symlink/relative-path resolution is still
# covered by the gui_recover_watch test above.)

# The viewer shows 1Password's own tray icon (locked/unlocked art) and reads its window titles for the
# tray menu, so op no longer runs a background poller to feed it.
@test "op gui only opens the app: it leaves no background poller behind" {
  run "$OP" gui
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -f "$ONEP_CONFIG_DIR/lock-poll.pid" ]
  ! grep -q 'lock_poll\|LOCK_STATE' "$OP" || return 1
}
