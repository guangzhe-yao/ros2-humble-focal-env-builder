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
OFFLINE_OUT_DIR="${OFFLINE_OUT_DIR:-$OUT_DIR/artifacts/offline}"
bundle_name="ros2-humble-focal-offline-bundle_${BUNDLE_VERSION}_amd64"

[[ "$BUNDLE_VERSION" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]] || {
  echo 'BUNDLE_VERSION must not contain paths or whitespace' >&2; exit 1;
}
for destination in "$RELEASE_DIR/$bundle_name.tar.gz" "$RELEASE_DIR/$bundle_name.tar.gz.sha256"; do
  [[ ! -e "$destination" && ! -L "$destination" ]] || {
    echo "Refusing to replace candidate: $destination; use a new version" >&2; exit 1;
  }
done

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
BUNDLE_NAME="$bundle_name" \
OFFLINE_OUT_DIR="$OFFLINE_OUT_DIR" \
BUILD_OFFLINE_BUNDLE=1 \
  "$REPO_ROOT/builder/package/repackage_existing_humble_artifacts.sh"

bundle="$OFFLINE_OUT_DIR/$bundle_name.tar.gz"
checksum="$bundle.sha256"

if [ ! -f "$bundle" ] || [ ! -f "$checksum" ]; then
  echo "Offline bundle was not generated under $OFFLINE_OUT_DIR" >&2
  exit 1
fi

(cd "$OFFLINE_OUT_DIR" && sha256sum -c "$(basename "$checksum")")
staging="$(mktemp -d "$RELEASE_DIR/.candidate.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp "$bundle" "$checksum" "$staging/"
# Hard links publish complete files and refuse to replace concurrent outputs.
ln "$staging/$(basename "$bundle")" "$RELEASE_DIR/$(basename "$bundle")"
ln "$staging/$(basename "$checksum")" "$RELEASE_DIR/$(basename "$checksum")"

printf '\nPico offline candidate is ready (latest unchanged):\n  %s\n  %s\n' \
  "$RELEASE_DIR/$(basename "$bundle")" \
  "$RELEASE_DIR/$(basename "$checksum")"
