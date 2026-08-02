# build/msc.sh -- sourced: locate the installed mavericks-shared-cmake scripts dir as $MSC.
MSC="${MSC_SCRIPTS:-}"
[ -d "$MSC" ] || MSC="$(cat "$HOME/.cmake/packages/MavericksSharedCMake/"* 2>/dev/null | head -1)/scripts"
[ -d "$MSC" ] || MSC="$(cd "$(dirname "$0")/.." && pwd)/../mavericks-shared-cmake/scripts"
[ -d "$MSC" ] || { echo "cannot locate mavericks-shared-cmake scripts (install it, or set MSC_SCRIPTS)" >&2; return 1 2>/dev/null || exit 1; }
export MSC
