#!/bin/sh
# platform: host-agnostic
_rc=0
if [ ! -f "$ROOT/usr/local/mavergreen/porthole/mavergreen.plist" ]; then
  echo "1Password for Mavericks needs Porthole installed first (it provides the viewer engine)." >&2
  echo "Install Porthole (https://github.com/Mavergreen/porthole), then run this installer again." >&2
  _rc=1
fi
if [ ! -f "$ROOT/usr/local/mavergreen/container-tools/mavergreen.plist" ]; then
  echo "1Password for Mavericks needs Container Tools for Mavericks installed first (it provides docker-machine)." >&2
  echo "Install it (https://github.com/Mavergreen/container-tools), then run this installer again." >&2
  _rc=1
fi
[ "$_rc" -eq 0 ]
