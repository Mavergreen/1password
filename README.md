# mavericks-1password

A [Porthole](https://github.com/Mavergreen/porthole) **preset** that runs 1Password on OS X 10.9
(Mavericks): a native-feeling "Linux 1Password.app" plus the `op` CLI.

This repo is not a viewer build -- it ships a parameter set (`1password.conf` + `1password.menu.json`)
and the hand-written `bin/op` CLI. Install Porthole once, then install this preset's `.pkg`:

- its postinstall runs `porthole materialize`, which renders the 1Password container recipe + launcher
  and drops **Linux 1Password.app** into `/Applications` (with its native menu bar); `sudo mavergreen
  uninstall 1password` removes that app along with the rest of the product;
- it installs `op` into `/usr/local/mavergreen/1password`, on the path through `/usr/local/mavergreen/bin`
  -- item management, `op gui`, lock/unlock, the 1Password SSH agent, and browser wiring. `op`
  resolves the shared `/Applications/Porthole.app` engine and the materialized container recipe at
  runtime.

- **Prerequisites:** Porthole and Container Tools for Mavericks (both enforced by `preinstall`).
- **Version:** `<1password-version>-mavericks.N`. 1Password has no public version feed, so
  `UPSTREAM_VERSION` is hand-bumped; the container floats to the latest 1Password at first launch
  (`UPDATE=float`, since 1Password self-gates server-side).
