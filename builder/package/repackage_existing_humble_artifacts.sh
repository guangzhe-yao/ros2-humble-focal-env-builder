#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

UNIFIED_PREFIX="${UNIFIED_PREFIX:-$HOME/ros2_humble_unified/install_deploy}"
OUT_DIR="${OUT_DIR:-$HOME/ros2_humble_unified/package_out}"
OFFLINE_OUT_DIR="${OFFLINE_OUT_DIR:-$OUT_DIR/artifacts/offline}"
BUILD_BASE="${BUILD_BASE:-$HOME/ros2_humble/build_deploy}"
PROFILE="${PROFILE:-$REPO_ROOT/profiles/third_party.lock.repos}"
SOURCE_LOCK="${SOURCE_LOCK:-$OUT_DIR/source-lock.repos}"
PKG_NAME="${PKG_NAME:-ros2-humble-focal-desktop-source}"
PKG_VERSION="${PKG_VERSION:-0.3.3+$(date +%Y%m%d%H%M)}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/ros/humble}"
BUILD_OFFLINE_BUNDLE="${BUILD_OFFLINE_BUNDLE:-0}"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

require_inputs() {
  if [ ! -f "$UNIFIED_PREFIX/setup.bash" ]; then
    echo "Missing existing unified install space: $UNIFIED_PREFIX/setup.bash" >&2
    exit 1
  fi
  if [ ! -f "$PROFILE" ]; then
    echo "Missing third-party profile: $PROFILE" >&2
    exit 1
  fi
}

copy_artifact_metadata() {
  local artifacts="$OUT_DIR/artifacts"
  cp "$PROFILE" "$artifacts/third_party.repos"
  if [ -f "$SOURCE_LOCK" ]; then
    cp "$SOURCE_LOCK" "$artifacts/source-lock.repos"
  else
    cp "$PROFILE" "$artifacts/source-lock.repos"
  fi
}

main() {
  require_inputs
  log "Repackaging existing unified Humble install space: $UNIFIED_PREFIX"
  SRC_PREFIX="$UNIFIED_PREFIX" \
  OUT_DIR="$OUT_DIR" \
  PKG_NAME="$PKG_NAME" \
  PKG_VERSION="$PKG_VERSION" \
  INSTALL_PREFIX="$INSTALL_PREFIX" \
  BUILD_BASE="$BUILD_BASE" \
  "$REPO_ROOT/builder/package/build_ros2_humble_bundle.sh"

  copy_artifact_metadata

  if [ "$BUILD_OFFLINE_BUNDLE" = "1" ]; then
    log "Building offline deploy bundle"
    ARTIFACT_DIR="$OUT_DIR/artifacts" \
      OUT_DIR="$OFFLINE_OUT_DIR" \
      "$REPO_ROOT/builder/package/build_offline_humble_bundle.sh"
  fi

  log "Done. Artifacts are under: $OUT_DIR/artifacts"
}

main "$@"
