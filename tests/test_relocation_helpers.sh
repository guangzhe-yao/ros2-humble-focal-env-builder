#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

SRC_PREFIX=/opt/ros/humble
OUT_DIR="$tmp_dir/out"
PKG_VERSION=0.0.0-test
BUILD_BASE=/home/nav01/ros2_humble/build_deploy
# shellcheck source=../builder/package/build_ros2_humble_bundle.sh
source "$REPO_ROOT/builder/package/build_ros2_humble_bundle.sh"

STAGED_PREFIX="$tmp_dir/stage"
index_dir="$STAGED_PREFIX/share/ament_index/resource_index/parent_prefix_path"
mkdir -p "$index_dir"
printf '%s' \
  '/home/nav01/jenkins_workspace/install/foo:/opt/ros/humble:/home/nav01/ros2_humble/install_deploy' \
  > "$index_dir/test_package"

normalize_parent_prefix_paths
if [ "$(<"$index_dir/test_package")" != "/opt/ros/humble" ]; then
  echo "Parent-prefix normalization failed" >&2
  exit 1
fi

if command -v patchelf >/dev/null 2>&1; then
  mkdir -p "$BUILD_DIR"
  : > "$BUILD_DIR/patched-rpaths.txt"
  cp /bin/true "$tmp_dir/test-elf"
  patchelf --set-rpath \
    '/home/nav01/ros2_humble/build_deploy/action_msgs:/home/nav01/ros2_humble/install_deploy/lib:/home/nav01/jenkins_workspace/build:/opt/ros/humble/lib:$ORIGIN' \
    "$tmp_dir/test-elf"
  rewrite_one_rpath "$tmp_dir/test-elf"
  actual_rpath="$(patchelf --print-rpath "$tmp_dir/test-elf")"
  if [ "$actual_rpath" != '/opt/ros/humble/lib:$ORIGIN' ]; then
    echo "RPATH relocation failed: $actual_rpath" >&2
    exit 1
  fi
fi

echo "Relocation helper test passed."
