# 1Password 8 for Mavericks

Linux 1Password 8 as a Mac OS X 10.9 Mavericks app.

(1Password 8 for Mac requires macOS 12 Monterey or later.)

## Usage

1. Install
   [Porthole](https://github.com/Mavergreen/porthole)
2. Install this
3. Open `/Applications/Linux 1Password.app`

## Also included

Upstream's Firefox plugin already works in Momiji and PowerFox.

- Shared lock state with the Firefox plugin
- the `op` CLI, which talks to the running app and shares its lock state
- the SSH agent at `~/.1password/agent.sock`, there while the app runs with Settings → Developer →
  "Use the SSH agent" ticked
- "Start at login" in the app's settings, kept in step with the Mac's Login Items
- `onepassword://` links
- Quick Access

To allow another browser, add its application name (such as `Google Chrome.app`) to
`/etc/1password/custom_allowed_browsers`, which must stay owned and writable only by root.
