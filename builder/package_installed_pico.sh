#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PREFIX="${SOURCE_PREFIX:-/opt/ros/humble}"
WORK_DIR="${WORK_DIR:-$HOME/ros2_humble_release_build}"
OUT_DIR="${OUT_DIR:-$WORK_DIR/package_out}"
RELEASE_DIR="${RELEASE_DIR:-$REPO_ROOT/release/pico}"
PKG_VERSION="${PKG_VERSION:-0.3.3+$(date +%Y%m%d%H%M)}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$(date +%Y%m%d%H%M)}"
PROFILE="${PROFILE:-$REPO_ROOT/profiles/third_party.lock.repos}"

if [ ! -f "$SOURCE_PREFIX/setup.bash" ]; then
  echo "Missing installed Humble environment: $SOURCE_PREFIX/setup.bash" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"

UNIFIED_PREFIX="$SOURCE_PREFIX" \
OUT_DIR="$OUT_DIR" \
PROFILE="$PROFILE" \
PKG_VERSION="$PKG_VERSION" \
BUNDLE_VERSION="$BUNDLE_VERSION" \
BUILD_OFFLINE_BUNDLE=1 \
  "$REPO_ROOT/builder/package/repackage_existing_humble_artifacts.sh"

offline_dir="$OUT_DIR/artifacts/offline"
bundle="$offline_dir/ros2-humble-focal-offline-bundle_${BUNDLE_VERSION}_amd64.tar.gz"
checksum="$bundle.sha256"

if [ ! -f "$bundle" ] || [ ! -f "$checksum" ]; then
  echo "Offline bundle was not generated under $offline_dir" >&2
  exit 1
fi

cp -f "$bundle" "$checksum" "$RELEASE_DIR/"
ln -sfn "$(basename "$bundle")" \
  "$RELEASE_DIR/ros2-humble-focal-offline-bundle_latest_amd64.tar.gz"
ln -sfn "$(basename "$checksum")" \
  "$RELEASE_DIR/ros2-humble-focal-offline-bundle_latest_amd64.tar.gz.sha256"

printf '\nPico offline release is ready:\n  %s\n  %s\n' \
  "$RELEASE_DIR/$(basename "$bundle")" \
  "$RELEASE_DIR/$(basename "$checksum")"
