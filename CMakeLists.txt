cmake_minimum_required(VERSION 3.16)

# 10.9 target/arch, set before project() so it reaches the Porthole sub-build.
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.9" CACHE STRING "Minimum macOS version")
set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "Target architectures")

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" MAVERICKS_1PW_VERSION LIMIT_COUNT 1)
project(mavericks-1password VERSION ${MAVERICKS_1PW_VERSION} LANGUAGES OBJC)

# This repo builds the 1Password product's viewer: honest "Linux 1Password" display name,
# identity slug "1password". Set before add_subdirectory(porthole) so these CACHE values
# win over the porthole sub-build's defaults.
set(PORTHOLE_APP_NAME "Linux 1Password" CACHE STRING "Display name for the generated viewer app")
set(PORTHOLE_APP_SLUG "1password" CACHE STRING "App identity slug (bundle-id suffix + per-app behavior key)")

# Explicit icon decision (forced by shared-cmake's mavericks_require_icon; the engine no
# longer defaults to any app). 1Password's icon is pulled at configure time from the
# running op-gui container -- never committed. (To build without it: -DMAVERICKS_ALLOW_GENERIC_ICON=ON.)
set(PORTHOLE_ICON_CONTAINER "op-gui" CACHE STRING "Container to extract the 1Password icon from")
set(PORTHOLE_ICON_GLOB "/opt/1Password/resources/icons/hicolor/512x512/apps/*.png"
    CACHE STRING "In-container glob for the 1Password icon PNG")

# Shared mavericks-* build conventions. Install the mavericks-shared-cmake
# package once (`cmake --install`, which self-registers in the user package
# registry); then it is found with no CMAKE_PREFIX_PATH.
# See github.com/ModernMavericks/shared-cmake. CI installs it via the shared
# action pinned to @v1 (the moving major tag; Renovate's github-actions manager
# tracks it). Pin a specific vX.Y.Z there if you ever need an exact repro.
find_package(MavericksSharedCMake REQUIRED)
set(MAVERICKS_REQUIRE_LANGS OBJC)
include(Mavericks)

enable_testing()
find_program(BATS_EXECUTABLE bats)   # used by both the product tests here and the engine's

# Locate the Porthole engine (its viewer is built for this product's GUI): an explicit
# -DPORTHOLE_DIR wins, then $PORTHOLE_DIR from the environment (porthole's install action
# exports it in CI), then a sibling checkout for local dev. Never a hardcoded CI path.
set(_ph_default "${CMAKE_SOURCE_DIR}/../mavericks-porthole")
if(DEFINED ENV{PORTHOLE_DIR} AND NOT "$ENV{PORTHOLE_DIR}" STREQUAL "")
  set(_ph_default "$ENV{PORTHOLE_DIR}")
endif()
set(PORTHOLE_DIR "${_ph_default}" CACHE PATH "Path to the porthole engine (sibling locally; install action sets it in CI)")
if(NOT EXISTS "${PORTHOLE_DIR}/viewer/CMakeLists.txt")
  message(FATAL_ERROR "porthole engine not found at ${PORTHOLE_DIR} -- clone ModernMavericks/porthole as a sibling, or set -DPORTHOLE_DIR")
endif()
add_subdirectory("${PORTHOLE_DIR}/viewer" porthole-viewer)

# Product BATS suites: the op CLI, 1Password container, packaging, browser wiring,
# ssh-agent. Registered per-suite so ctest reports them individually. (Engine suites are
# registered by porthole/CMakeLists.txt.)
if(BATS_EXECUTABLE)
  file(GLOB _bats "${CMAKE_CURRENT_SOURCE_DIR}/tests/*.bats")
  foreach(_b IN LISTS _bats)
    # Skip AppleDouble sidecar files (._foo.bats) that macOS scatters on non-native
    # filesystems (the VMware HGFS share): their NAME_WE is empty -> add_test rejects it.
    get_filename_component(_leaf "${_b}" NAME)
    if(_leaf MATCHES "^\\._")
      continue()
    endif()
    get_filename_component(_name "${_b}" NAME_WE)
    add_test(NAME ${_name} COMMAND ${BATS_EXECUTABLE} "${_b}")
    set_tests_properties(${_name} PROPERTIES WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
  endforeach()
else()
  message(STATUS "bats not found -- BATS suites won't run via ctest (install bats to enable)")
endif()

# `cmake --build . --target pkg` builds the installer (was `make pkg`).
add_custom_target(pkg
  COMMAND sh "${CMAKE_CURRENT_SOURCE_DIR}/packaging/macos/build_pkg.sh"
             "${PROJECT_VERSION}" "mavericks-1password-${PROJECT_VERSION}.pkg"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  USES_TERMINAL
  COMMENT "Building mavericks-1password-${PROJECT_VERSION}.pkg")
