#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${ARTIFACT_DIR:?Set ARTIFACT_DIR to the rebuilt base artifacts}"
: "${EXTRA_APT_DEBS_DIR:?Set colon-separated module, vendor and marker DEB directories}"
export BUNDLE_NAME="${BUNDLE_NAME:-robot-humble-focal-offline-20261015-amd64}"
export FAIL_ON_MISSING_APT_DEBS=1
export ENABLE_OSRF_GAZEBO_SOURCE=0
source "$REPO/builder/package/build_offline_humble_bundle.sh"
require_focal_amd64
require_artifacts
prepare_bundle_root
collect_root_deps
resolve_apt_closure
download_apt_debs
write_apt_repo_index
cp "$REPO/deploy/pico/install_robot_delivery.sh" "$BUNDLE_ROOT/install.sh"
cp "$REPO/deploy/pico/robot_delivery_README.md" "$BUNDLE_ROOT/README.md"
cp "$REPO/tests/verify_robot_delivery.sh" "$BUNDLE_ROOT/verify-installation.sh"
chmod +x "$BUNDLE_ROOT/install.sh" "$BUNDLE_ROOT/verify-installation.sh"
for deb in "$APT_DEBS_DIR"/*.deb; do
  name="$(dpkg-deb -f "$deb" Package)"
  case "$name" in
    ros2-humble-focal-desktop-source|ros-humble-*|zj-humanoid-*)
      printf '%s=%s\n' "$name" "$(dpkg-deb -f "$deb" Version)";;
  esac
done | sort -u > "$BUNDLE_ROOT/root-packages.txt"
(
  cd "$BUNDLE_ROOT"
  find apt_debs -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum install.sh root-packages.txt README.md verify-installation.sh >> SHA256SUMS
)
bash "$BUNDLE_ROOT/install.sh" --check
tar -czf "$OUT_DIR/$BUNDLE_NAME.tar.gz" -C "$OUT_DIR" "$BUNDLE_NAME"
(cd "$OUT_DIR"; sha256sum "$BUNDLE_NAME.tar.gz" > "$BUNDLE_NAME.tar.gz.sha256")
echo "Built $OUT_DIR/$BUNDLE_NAME.tar.gz"
