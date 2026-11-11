#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
reject() {
  if ("$@"); then echo "Expected refusal: $*" >&2; exit 1; fi
}
(
  source "$REPO/builder/package/build_ros2_humble_bundle.sh"
  BUILD_DIR="$temp/build" ARTIFACT_DIR="$temp/artifacts"
  PKGROOT="$BUILD_DIR/pkg" STAGED_PREFIX="$PKGROOT/opt/ros/humble"
  mkdir -p "$ARTIFACT_DIR"
  touch "$ARTIFACT_DIR/preserve.deb"
  reject prepare_dirs
  [[ -f "$ARTIFACT_DIR/preserve.deb" ]]
)
(
  source "$REPO/builder/build_unified_humble_env.sh"
  BASE_PREFIX="$temp/base" PROFILE="$temp/profile"
  mkdir -p "$BASE_PREFIX"
  touch "$BASE_PREFIX/setup.bash" "$PROFILE"
  UNIFIED_PREFIX="$BASE_PREFIX" BUILD_DIR="$temp/new-build" LOG_DIR="$temp/new-log"
  SRC_DIR="$temp/new-src" OUT_DIR="$temp/new-out"
  reject prepare_workspace
  [[ -f "$BASE_PREFIX/setup.bash" ]]
)
(
  source "$REPO/builder/bootstrap_humble_focal_env.sh"
  BASE_PREFIX="$temp/base" BASE_BUILD_DIR="$temp/base-build" BASE_LOG_DIR="$temp/base-log"
  BASE_BUILD_MARKER="$temp/marker" BASE_SRC_DIR="$temp/src" BASE_IMPORT_MARKER="$temp/imported"
  reject build_base_humble
  mkdir -p "$BASE_SRC_DIR"
  touch "$BASE_SRC_DIR/preserve"
  reject import_ros2_sources
  CLEAN_BASE=1
  reject import_ros2_sources
  [[ -f "$BASE_SRC_DIR/preserve" && -f "$BASE_PREFIX/setup.bash" ]]
)
echo 'Build and packaging entries preserve existing directories.'
