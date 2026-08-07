#!/bin/sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
exec sh "$SHIPYARD/release-notes-file.sh" "${1:?TAG required}" "${2:?FULL version required}" "Linux 1Password"
