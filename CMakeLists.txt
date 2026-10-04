cmake_minimum_required(VERSION 3.16)
# The 1Password preset compiles nothing but its Sparkle updater, built here by build/build-updater.sh.
project(OnePasswordUpdater LANGUAGES OBJC)

find_package(MavericksShipyard REQUIRED)
include(Mavericks)
include(MavericksSparkle)

# The release's version (the tag, or build/version.sh): the updater compares it with the feed's.
if(NOT ONEP_VERSION)
  mavericks_resolve_version(ONEP_VERSION)
endif()

mavericks_add_updater_app(
  PRODUCT 1password
  PRODUCT_NAME "1Password for Mavericks"
  ALLOW_GENERIC   # 1Password's mark isn't ours to borrow
  VERSION "${ONEP_VERSION}"
  CONFIRM_TITLE "1Password for Mavericks updated"
  CONFIRM_BODY "Linux 1Password was updated. Choose Restart to Update in its app menu to use the new version."
)
