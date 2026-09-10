#!/bin/sh
# Print the URL of the release notes for one upstream 1Password for Linux version. shipyard's
# upstream-notes.sh links it from our release notes when a release ships a NEW upstream.
#   usage: upstream-release-notes-url.sh <upstream-version>      (bare: 8.12.30)
# /linux/stable/ keeps the whole history; /linux/<minor>/ redirects there and drops the #anchor.
set -eu
printf 'https://releases.1password.com/linux/stable/#1password-for-linux-%s\n' "${1:?usage: upstream-release-notes-url.sh <upstream-version>}"
