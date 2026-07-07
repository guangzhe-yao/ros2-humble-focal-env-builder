#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNIFIED_PREFIX="${UNIFIED_PREFIX:-$HOME/ros2_humble_unified/install_deploy}"
OUT_DIR="${OUT_DIR:-$HOME/ros2_humble_unified/package_out}"
BUILD_BASE="${BUILD_BASE:-$HOME/ros2_humble/build_deploy}"
PROFILE="${PROFILE:-$REPO_ROOT/profiles/third_party.lock.repos}"
SOURCE_LOCK="${SOURCE_LOCK:-$OUT_DIR/source-lock.repos}"
PKG_NAME="${PKG_NAME:-ros2-humble-focal-desktop-source}"
PKG_VERSION="${PKG_VERSION:-0.3.0+$(date +%Y%m%d%H%M)}"
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
  fi
  cp "$REPO_ROOT/scripts/verify_installed_humble_env.sh" "$artifacts/verify_installed_humble_env.sh"
  chmod 0755 "$artifacts/verify_installed_humble_env.sh"

  if [ -d "$REPO_ROOT/deploy/orin_pico_cyclonedds" ]; then
    mkdir -p "$artifacts/orin_pico_cyclonedds"
    rsync -a --delete \
      --exclude '__pycache__/' \
      --exclude '*.pyc' \
      "$REPO_ROOT/deploy/orin_pico_cyclonedds/" \
      "$artifacts/orin_pico_cyclonedds/"
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
  "$REPO_ROOT/packaging/build_ros2_humble_bundle.sh"

  copy_artifact_metadata

  if [ "$BUILD_OFFLINE_BUNDLE" = "1" ]; then
    log "Building offline deploy bundle"
    ARTIFACT_DIR="$OUT_DIR/artifacts" \
      "$REPO_ROOT/packaging/build_offline_humble_bundle.sh"
  fi

  log "Done. Artifacts are under: $OUT_DIR/artifacts"
}

main "$@"
