# Build ingredients

`mavericks-1password` is a Porthole **preset** that ports 1Password. The shipped `.pkg` is small --
the preset conf (`1password.conf` + `1password.menu.json`) and the `bin/op` CLI; the container image
+ GUI launcher are rendered on the user's Mac by `porthole materialize`.

| Ingredient | Pinned in | Renovate | On a change |
|---|---|---|---|
| 1Password (own upstream) | `UPSTREAM_VERSION` | manual — 1Password ships no public version feed, so the number is **hand-bumped** (it only names the release; the container floats) | edit `UPSTREAM_VERSION`, push to main → auto-cuts `<version>-mavericks.1` |
| Porthole engine (runtime prerequisite) | not baked — `preinstall` requires it installed | github-actions manager (the `@v1` install action used in CI) | user updates Porthole itself (Sparkle) |
| clang22 (the compiler for the Sparkle updater) | `components/clang22/version` — one `22.X.Y-mavericks.N` release tag | regex manager on `Mavergreen/clang-22` github-releases | `build/build-updater.sh` takes that release from shipyard's `fetch_clang22.sh` on any host; a bump rebuilds the updater in CI and ships with the next release |
| shipyard (release tooling + gate) | `Mavergreen/shipyard@v1` (install action) | github-actions manager tracks the `@v1` tag | `@v1` is a moving tag |

The container is `UPDATE=float` (see `1password.conf`): 1Password self-gates on a server-side minimum
version, so pinning is pointless -- it installs current at first launch. `UPSTREAM_VERSION` names the
release for the 1Password version current when it is cut; bump it by hand when 1Password ships an update
you want to name a release for.

## Versioning

- port

## Conformance deviations

- no-standalone: a Porthole preset, which the family lists as having no standalone form. Its tree is a recipe (the preset conf and menu manifest) plus glue that names the installed tree; the app itself is generated on the Mac by the installed Porthole at install time, so an unpacked directory holds nothing that runs. Reconsider if a preset ever ships a runnable app in its payload.
- install-path:Library/Application*/Mozilla/NativeMessagingHosts/com.1password.1password.json: Momiji and PowerFox find a native-messaging host only by a manifest in `Library/Application Support/Mozilla/NativeMessagingHosts/`, a place Firefox dictates, so the pkg installs `com.1password.1password.json` there for the 1Password extension. The manifest names the bridge in this product's tree, `usr/local/mavergreen/1password/libexec/op-browser-bridge`, and is listed in the manifest's `outside`, so uninstall removes it.
- on-target: no 10.9 acceptance job yet; exit: a release.yml job on Mavergreen/mavericks-vm@v1 that installs this run's pkg in the guest and runs what it ships, which publish needs
