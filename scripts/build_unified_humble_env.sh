#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_PREFIX="${BASE_PREFIX:-$HOME/ros2_humble/install_deploy}"
WORK_DIR="${WORK_DIR:-$HOME/ros2_humble_unified}"
PROFILE="${PROFILE:-$REPO_ROOT/profiles/third_party.repos}"
SOURCE_CACHE_DIR="${SOURCE_CACHE_DIR:-}"
SRC_DIR="${SRC_DIR:-$WORK_DIR/src}"
UNIFIED_PREFIX="${UNIFIED_PREFIX:-$WORK_DIR/install_deploy}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"
LOG_DIR="${LOG_DIR:-$WORK_DIR/log}"
OUT_DIR="${OUT_DIR:-$WORK_DIR/package_out}"
PKG_NAME="${PKG_NAME:-ros2-humble-focal-desktop-source}"
PKG_VERSION="${PKG_VERSION:-0.2.0+$(date +%Y%m%d%H%M)}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/ros/humble}"
BUILD_BASE="${BUILD_BASE:-$HOME/ros2_humble/build_deploy}"
ROSDEP_USE_MIRROR="${ROSDEP_USE_MIRROR:-auto}"
ROSDEP_ROSDISTRO_MIRROR="${ROSDEP_ROSDISTRO_MIRROR:-https://mirrors.ustc.edu.cn/rosdistro}"
COLCON_PACKAGES_ARGS="${COLCON_PACKAGES_ARGS:-}"
AMENT_PREFIX_PATH="${AMENT_PREFIX_PATH:-}"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

source_ros_setup() {
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set -u
}

require_focal_amd64() {
  . /etc/os-release
  if [ "${VERSION_CODENAME:-}" != "focal" ]; then
    echo "This build must run on Ubuntu 20.04 focal; got ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo "This build currently supports amd64 only; got $(dpkg --print-architecture)" >&2
    exit 1
  fi
}

require_tools() {
  local missing=()
  for tool in git vcs colcon rosdep rsync dpkg-deb patchelf python3 cmake curl; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing tools: ${missing[*]}" >&2
    echo "Install build host dependencies first: sudo apt-get install -y build-essential git python3-vcstool python3-rosdep python3-colcon-common-extensions python3-pip patchelf rsync" >&2
    exit 1
  fi
}

configure_rosdep_network() {
  local mode="$ROSDEP_USE_MIRROR"
  local mirror="$ROSDEP_ROSDISTRO_MIRROR"
  local raw_probe="https://raw.githubusercontent.com/ros/rosdistro/master/rosdep/base.yaml"
  local default_list="/etc/ros/rosdep/sources.list.d/20-default.list"
  local index_url_file="/etc/ros/rosdep/rosdistro_index_url"
  local mirror_hostpath="${mirror#https://}"
  mirror_hostpath="${mirror_hostpath#http://}"

  if [ "$mode" = "0" ] || [ "$mode" = "false" ]; then
    return 0
  fi
  if [ -f "$default_list" ] &&
     grep -Fq "$mirror/rosdep/base.yaml" "$default_list" &&
     [ -f "$index_url_file" ]; then
    export ROSDISTRO_INDEX_URL
    ROSDISTRO_INDEX_URL="$(head -n 1 "$index_url_file")"
    log "Using existing rosdep mirror configuration: $ROSDISTRO_INDEX_URL"
    return 0
  fi
  if [ "$mode" = "auto" ] && curl -fsSL --connect-timeout 5 --max-time 8 "$raw_probe" >/dev/null 2>&1; then
    return 0
  fi

  log "Configuring rosdep rosdistro mirror: $mirror"
  sudo mkdir -p /etc/ros/rosdep/sources.list.d /etc/ros/rosdep
  local tmp_list
  tmp_list="$(mktemp)"
  curl -fsSL --connect-timeout 10 --max-time 30 "$mirror/rosdep/sources.list.d/20-default.list" -o "$tmp_list"
  if [ -f "$default_list" ] && [ ! -f "$default_list.before-mirror" ]; then
    sudo cp "$default_list" "$default_list.before-mirror"
  fi
  sed \
    -e "s#https://raw.githubusercontent.com/ros/rosdistro/master#$mirror#g" \
    -e "s#http://raw.githubusercontent.com/ros/rosdistro/master#$mirror#g" \
    -e "s#raw.githubusercontent.com/ros/rosdistro/master#$mirror_hostpath#g" \
    "$tmp_list" | sudo tee "$default_list" >/dev/null
  printf '%s\n' "$mirror/index-v4.yaml" | sudo tee "$index_url_file" >/dev/null
  rm -f "$tmp_list"
  export ROSDISTRO_INDEX_URL="$mirror/index-v4.yaml"
}

ensure_new_cmake() {
  local version
  version="$(cmake --version 2>/dev/null | awk '/version/ {print $3; exit}' || true)"
  if [ -n "$version" ] && dpkg --compare-versions "$version" ge 3.22; then
    log "CMake is new enough: $version"
    return 0
  fi

  log "Installing user-level CMake >= 3.22 for current Focal overlay builds"
  python3 -m pip install --user 'cmake>=3.22,<3.29'
  export PATH="$HOME/.local/bin:$PATH"
  cmake --version | head -n 1
}

update_rosdep_cache() {
  if rosdep update; then
    return 0
  fi

  echo "Warning: rosdep update reported a partial network failure; validating the resulting cache." >&2
  if rosdep resolve cmake --rosdistro humble --os=ubuntu:focal >/dev/null 2>&1 &&
     rosdep resolve rclcpp --rosdistro humble --os=ubuntu:focal >/dev/null 2>&1; then
    echo "rosdep cache is usable; continuing after partial update failure." >&2
    return 0
  fi

  echo "rosdep cache is not usable after update failure." >&2
  return 1
}

prepare_workspace() {
  if [ ! -f "$BASE_PREFIX/setup.bash" ]; then
    echo "Missing base ROS install space: $BASE_PREFIX/setup.bash" >&2
    exit 1
  fi
  if [ ! -f "$PROFILE" ]; then
    echo "Missing profile file: $PROFILE" >&2
    exit 1
  fi

  log "Preparing clean unified install prefix: $UNIFIED_PREFIX"
  rm -rf "$UNIFIED_PREFIX" "$BUILD_DIR" "$LOG_DIR" "$SRC_DIR" "$OUT_DIR"
  mkdir -p "$WORK_DIR" "$SRC_DIR" "$OUT_DIR"
  rsync -aL --delete \
    --exclude '__pycache__/' \
    --exclude '*.pyc' \
    "$BASE_PREFIX/" "$UNIFIED_PREFIX/"
}

import_sources() {
  if [ -n "$SOURCE_CACHE_DIR" ]; then
    if [ ! -d "$SOURCE_CACHE_DIR" ]; then
      echo "Missing source cache directory: $SOURCE_CACHE_DIR" >&2
      exit 1
    fi
    log "Copying third-party sources from cache: $SOURCE_CACHE_DIR"
    rsync -a --delete "$SOURCE_CACHE_DIR/" "$SRC_DIR/"
  else
    log "Importing third-party sources from $PROFILE"
    vcs import "$SRC_DIR" < "$PROFILE"
  fi
  vcs export --exact "$SRC_DIR" > "$OUT_DIR/source-lock.repos"
}

check_duplicate_packages() {
  log "Checking duplicate package names in third-party source tree"
  local duplicates
  duplicates="$(cd "$WORK_DIR" && colcon list --base-paths "$SRC_DIR" --names-only | sort | uniq -d || true)"
  if [ -n "$duplicates" ]; then
    echo "Duplicate package names found in source tree:" >&2
    printf '%s\n' "$duplicates" >&2
    exit 1
  fi
}

install_dependencies() {
  log "Installing rosdep dependencies"
  source_ros_setup "$UNIFIED_PREFIX/setup.bash"
  update_rosdep_cache
  rosdep install --from-paths "$SRC_DIR" --ignore-src -y --os=ubuntu:focal --rosdistro humble
}

build_overlay_into_unified_prefix() {
  log "Building third-party overlay into $UNIFIED_PREFIX"
  source_ros_setup "$UNIFIED_PREFIX/setup.bash"
  export PATH="$HOME/.local/bin:$PATH"
  cd "$WORK_DIR"

  # Intentionally no --symlink-install: release artifacts must not contain links
  # back to the transient source or build directories.
  colcon --log-base "$LOG_DIR" build \
    --merge-install \
    --base-paths "$SRC_DIR" \
    --install-base "$UNIFIED_PREFIX" \
    --build-base "$BUILD_DIR" \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    $COLCON_PACKAGES_ARGS
}

verify_unified_prefix() {
  log "Running smoke checks"
  source_ros_setup "$UNIFIED_PREFIX/setup.bash"
  ros2 pkg prefix rclcpp >/dev/null
  ros2 pkg prefix rviz2 >/dev/null

  if ros2 pkg list | grep -qx controller_manager; then
    ros2 pkg prefix controller_manager >/dev/null
    ros2 control --help >/dev/null
  fi

  rosdep check --from-paths "$SRC_DIR" --ignore-src --os=ubuntu:focal --rosdistro humble
}

package_unified_prefix() {
  log "Packaging unified ROS 2 Humble environment"
  SRC_PREFIX="$UNIFIED_PREFIX" \
  OUT_DIR="$OUT_DIR" \
  PKG_NAME="$PKG_NAME" \
  PKG_VERSION="$PKG_VERSION" \
  INSTALL_PREFIX="$INSTALL_PREFIX" \
  BUILD_BASE="$BUILD_BASE" \
  "$REPO_ROOT/packaging/build_ros2_humble_bundle.sh"

  cp "$PROFILE" "$OUT_DIR/artifacts/third_party.repos"
  cp "$OUT_DIR/source-lock.repos" "$OUT_DIR/artifacts/source-lock.repos"
  cp "$REPO_ROOT/scripts/verify_installed_humble_env.sh" "$OUT_DIR/artifacts/verify_installed_humble_env.sh"
  chmod 0755 "$OUT_DIR/artifacts/verify_installed_humble_env.sh"
}

main() {
  require_focal_amd64
  require_tools
  configure_rosdep_network
  ensure_new_cmake
  prepare_workspace
  import_sources
  check_duplicate_packages
  install_dependencies
  build_overlay_into_unified_prefix
  verify_unified_prefix
  package_unified_prefix

  log "Done. Artifacts are under: $OUT_DIR/artifacts"
}

main "$@"
