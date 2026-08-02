# op — 1Password CLI + GUI on OS X Mavericks (Docker-backed)

Full 1Password access (CLI and the real desktop GUI) on OS X 10.9, by running
the current Linux `op` CLI and the 1Password 8 Linux app in one Docker
container (`op-gui`) on the docker-machine VM. Why: no supported 1Password
client runs natively on 10.9, and the web vault is broken by a Momiji OPFS
bug (`docs/momiji-opfs-truncate-bug-report.md`). Designs:
`docs/superpowers/specs/2026-07-07-mavericks-1password-design.md` (CLI) and
`docs/superpowers/specs/2026-07-08-gui-container-design.md` (GUI).

## Install

1. **Install Docker for Mavericks** (the `docker-machine` VM) if you haven't —
   this rig drives it and won't install without it.
2. **Download** `mavericks-1password-X.Y.Z.pkg` from the latest
   [GitHub Release](../../releases/latest).
3. **Right-click the pkg → Open** (first-run Gatekeeper on 10.9), then
   Continue → Install (admin password). Installs `op` to `/usr/local/bin/op`.
4. `op setup`   — builds the container image; prompts for account + Secret Key.
5. `op signin`  — caches a session. Then `op gui` for the desktop app.

Optional: `op ssh-agent install-launchd` and `op watch install-launchd` keep
the SSH agent and approval-notifier running across logins.

(From source instead: `ln -s "$PWD/bin/op" /usr/local/bin/op`, then `op setup`.)

## Use

    op item list                                   # real op grammar, verbatim
    op copy GitHub          # password -> clipboard (auto-clears in 45 s)
    op otp GitHub           # one-time code -> clipboard (auto-clears)
    op item get GitHub      # details (add --reveal to show secrets)
    op item get GitHub --fields username | op clip   # anything -> guarded clipboard
    op item edit GitHub username=amitai@example.com
    op item create --category login --title "Example Site" \
      --generate-password=letters,digits,symbols,32
    op gui                  # the real 1Password app, via Screen Sharing
    op gui stop             # shut the GUI container down
    op ssh-agent start      # 1Password SSH keys for ssh/git (needs socat)
    op ssh-agent install-launchd   # keep it running across logins
    op signout

Unrecognized commands go straight to the containerized `op` with the session
applied (`op whoami`, `op document get Passport`, ...). When you're at a
terminal, `op` gets a real TTY — interactive prompts and colors work; when
piped or scripted, output stays byte-clean for capture. Sessions expire after
~30 minutes idle; the wrapper re-prompts and retries automatically. If the VM
is down: `docker-machine start default`.

`op` reaches the VM through the `mavericks` docker context that Container Tools
for Mavericks keeps pointed at the running VM (so a VM restart / DHCP renumber
heals itself — no stale host cached). Without that context it falls back to a
`docker-machine env` snapshot. Override the context name with
`ONEP_DOCKER_CONTEXT`, or set it empty to force the snapshot path.

`op setup --rebuild` rebuilds the container image with the latest 1Password
releases (the app can't self-update inside the container). Geometry override:
`ONEP_GUI_GEOMETRY=1920x1080x24 op setup --rebuild`.

### 1Password SSH agent

Use SSH keys stored in 1Password for `ssh`/`git` on the Mac — keys never
leave 1Password; Mavericks only ever receives signatures, and the app must
be unlocked to serve them. One-time setup: install `socat` on the Mac
(`pkgin install socat`), and enable **Settings → Developer → Use the SSH
agent** in the app (`op gui`). Then:

    op ssh-agent start
    export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"   # add to your shell profile
    ssh-add -l                                           # lists your 1Password keys

`op ssh-agent install-launchd` keeps the tunnel up across logins;
`op ssh-agent status`/`stop` and `uninstall-launchd` manage it. For git commit
signing, set `git config --global gpg.format ssh` and `user.signingkey` to
your public key. The tunnel rides the same docker TLS channel as everything
else — no extra port, daemon, or keys.

## Security notes

- Master password: typed per session, never stored; travels over the
  TLS-verified docker-machine channel.
- Secret Key + device config: encrypted by `op` in the `op-config` Docker
  volume on the VM.
- Session token: `~/.config/1p/session`, mode 600. `op signout` kills it.
- Clipboard: cleared after 45 s unless you copied something else meanwhile.
- GUI: VNC on the VM's host-only address. `op gui` generates a VNC password
  and seeds it into your login keychain, so Screen Sharing connects silently
  and you never see it; the app's own lock screen gates the vault. The app's
  data lives encrypted in the `op-gui-data` volume, and its secrets keyring
  (a passwordless gnome-keyring, needed so it can save its 2FA token) lives
  in that volume too.

## Known issues

- **⌘-Tab out of the GUI**: while the Screen Sharing window has focus, ⌘-Tab
  can reach the Linux side instead of switching Mac apps. Workaround: after
  copying in the GUI (the clipboard bridges to the Mac automatically), click
  a Mac window or use Mission Control to hand focus back, then ⌘-Tab and
  paste. A smoother fix is still open.
- **CLI/app unlock sharing**: not wired up — the CLI uses its own session
  auth, independent of the GUI's unlock. See the GUI spec's experiment note.
- **SSH agent needs the app unlocked**: `ssh-add -l` shows "no identities"
  when the 1Password app is locked; unlock it (`op gui`) and retry.
- **First SSH signature needs approval**: using a key raises 1Password's
  "Allow Unknown Application to use the SSH key" prompt in the Screen Sharing
  window (`op gui`) — "Unknown" because the request arrives over the tunnel.
  Check **"Approve for all applications"** and authorize once; after that the
  agent vends signatures without prompting while the app is unlocked. (A
  fully non-GUI authorization path would require the desktop-integration
  "cookie" handshake — tracked as a future project, same root as CLI unlock
  sharing.)

## Tests

    make test          # or: bats tests/*.bats

BATS suite (needs bats: `pkgin install bats`) against stub
docker/pbcopy/pbpaste/etc.; nothing touches the real container or your
account. The shipped `bin/op` stays pure POSIX sh.

## Manual smoke checklist (real account; run after changes)

1. `op setup` — idempotent; second run says "already configured".
2. `op signin` — accepts master password; `~/.config/1p/session` exists, mode 600.
3. `op item list` — lists items (fallthrough to real op grammar).
4. `op item create --category login --title "op smoke test" --generate-password=letters,digits,symbols,32 username=smoke@example.com` — creates item.
5. `op item get "op smoke test"` — password concealed; `--reveal` shows it.
6. `op copy "op smoke test"` — paste somewhere: password; wait 45 s: clipboard empty.
7. `op item get "op smoke test" --fields username | op clip` — paste: username; auto-clears.
8. `op item edit "op smoke test" username=smoke2@example.com` — `op item get` reflects it.
9. `op item delete "op smoke test"` — cleanup.
10. `op signout` — session file gone; next command re-prompts.
11. `op gui` — Screen Sharing opens silently; app renders; GUI copy pastes on the Mac.
12. VM reboot (`docker-machine restart default`) — `op item list` and `op gui`
    both recover without re-running setup.

## Licensing / third-party

`op gui` launches the native Porthole client (`porthole/`), a from-scratch
Cocoa Xpra viewer built for this project. The 1Password name and icon belong to
AgileBits; the icon is extracted at build time from your own installed copy and
is not redistributed in this repository.
