# build/msc.sh -- sourced: locate the installed mavericks-shipyard scripts dir as $SHIPYARD.
SHIPYARD="${SHIPYARD_SCRIPTS:-}"
[ -d "$SHIPYARD" ] || SHIPYARD="$(cat "$HOME/.cmake/packages/MavericksShipyard/"* 2>/dev/null | head -1)/scripts"
[ -d "$SHIPYARD" ] || SHIPYARD="$(cd "$(dirname "$0")/.." && pwd)/../mavericks-shipyard/scripts"
[ -d "$SHIPYARD" ] || { echo "cannot locate mavericks-shipyard scripts (install it, or set SHIPYARD_SCRIPTS)" >&2; return 1 2>/dev/null || exit 1; }
export SHIPYARD
