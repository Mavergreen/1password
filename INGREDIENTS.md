# Build ingredients

`mavericks-1password` is a Porthole **preset** that ports 1Password. The shipped `.pkg` is small --
the preset conf (`1password.conf` + `1password.menu.json`) and the `bin/op` CLI; the container image
+ GUI launcher are rendered on the user's Mac by `porthole materialize`.

| Ingredient | Pinned in | Renovate | On a change |
|---|---|---|---|
| 1Password (own upstream) | `UPSTREAM_VERSION` | manual — 1Password ships no public version feed, so the number is **hand-bumped** (it only names the release; the container floats) | edit `UPSTREAM_VERSION`, push to main → auto-cuts `<version>-mavericks.1` |
| Porthole engine (runtime prerequisite) | not baked — `preinstall` requires it installed | github-actions manager (the `@v1` install action used in CI) | user updates Porthole itself (Sparkle) |
| shipyard (release tooling + gate) | `Mavergreen/shipyard@v1` (install action) | github-actions manager tracks the `@v1` tag | `@v1` is a moving tag |

The container is `UPDATE=float` (see `1password.conf`): 1Password self-gates on a server-side minimum
version, so pinning is pointless -- it installs current at first launch. `UPSTREAM_VERSION` names the
release for the 1Password version current when it is cut; bump it by hand when 1Password ships an update
you want to name a release for.

## Conformance deviations

- install-path:Library/Application*/Mozilla/NativeMessagingHosts/com.1password.1password.json: Momiji and PowerFox find a native-messaging host only by a manifest in `Library/Application Support/Mozilla/NativeMessagingHosts/`, a place Firefox dictates, so the pkg installs `com.1password.1password.json` there for the 1Password extension. The manifest names the bridge in this product's tree, `usr/local/mavergreen/1password/libexec/op-browser-bridge`, and is listed in the manifest's `outside`, so uninstall removes it.
