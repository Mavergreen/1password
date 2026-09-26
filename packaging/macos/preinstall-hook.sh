#!/bin/sh
# platform: host-agnostic
if [ ! -f "$ROOT/usr/local/mavergreen/porthole/mavergreen.plist" ]; then
  echo "1Password for Mavericks needs Porthole installed first (it provides the viewer engine)." >&2
  echo "Install Porthole (https://github.com/Mavergreen/porthole), then run this installer again." >&2
  false
fi
