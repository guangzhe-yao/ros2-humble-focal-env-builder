#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROS_DISTRO="${ROS_DISTRO:-humble}"
ROS2_REPOS_URL="${ROS2_REPOS_URL:-https://raw.githubusercontent.com/ros2/ros2/humble/ros2.repos}"
WORK_DIR="${WORK_DIR:-$HOME/ros2_humble}"
ROS2_REPOS_FILE="${ROS2_REPOS_FILE:-$REPO_ROOT/profiles/ros2_humble.repos}"
RESOLVED_ROS2_REPOS_FILE="${RESOLVED_ROS2_REPOS_FILE:-$WORK_DIR/ros2_humble.resolved.repos}"
BASE_SRC_DIR="${BASE_SRC_DIR:-$WORK_DIR/src}"
BASE_IMPORT_MARKER="${BASE_IMPORT_MARKER:-$WORK_DIR/.ros2_humble_import_complete}"
BASE_PREFIX="${BASE_PREFIX:-$WORK_DIR/install_deploy}"
BASE_BUILD_MARKER="${BASE_BUILD_MARKER:-$WORK_DIR/.ros2_humble_build_complete}"
BASE_BUILD_DIR="${BASE_BUILD_DIR:-$WORK_DIR/build_deploy}"
BASE_LOG_DIR="${BASE_LOG_DIR:-$WORK_DIR/log_deploy}"
UNIFIED_WORK_DIR="${UNIFIED_WORK_DIR:-$HOME/ros2_humble_unified}"
PROFILE="${PROFILE:-$REPO_ROOT/profiles/third_party.lock.repos}"
PKG_VERSION="${PKG_VERSION:-0.3.3+$(date +%Y%m%d%H%M)}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/ros/humble}"
INSTALL_AFTER_BUILD="${INSTALL_AFTER_BUILD:-1}"
CLEAN_BASE="${CLEAN_BASE:-0}"
REBUILD_BASE="${REBUILD_BASE:-0}"
COLCON_PARALLEL_WORKERS="${COLCON_PARALLEL_WORKERS:-2}"
CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$COLCON_PARALLEL_WORKERS}"
ROSDEP_USE_MIRROR="${ROSDEP_USE_MIRROR:-1}"
ROSDEP_ROSDISTRO_MIRROR="${ROSDEP_ROSDISTRO_MIRROR:-https://mirrors.ustc.edu.cn/rosdistro}"
ROSDEP_SKIP_KEYS="${ROSDEP_SKIP_KEYS:-fastcdr rti-connext-dds-6.0.1 urdfdom_headers libopencv-core libopencv-highgui libopencv-imgcodecs libopencv-imgproc libopencv-videoio}"
GITHUB_URL_PREFIX="${GITHUB_URL_PREFIX:-}"
GIT_INSTEADOF_GITHUB_PREFIX="${GIT_INSTEADOF_GITHUB_PREFIX:-}"
BASE_COLCON_PACKAGES_ARGS="${BASE_COLCON_PACKAGES_ARGS:-}"
BASE_COLCON_CMAKE_ARGS="${BASE_COLCON_CMAKE_ARGS:-}"
THIRD_PARTY_COLCON_PACKAGES_ARGS="${THIRD_PARTY_COLCON_PACKAGES_ARGS:-}"
THIRD_PARTY_COLCON_CMAKE_ARGS="${THIRD_PARTY_COLCON_CMAKE_ARGS:--DCMAKE_DISABLE_FIND_PACKAGE_Doxygen=TRUE}"
SUDO_KEEPALIVE_PID=""

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

source_ros_setup() {
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set -u
}

stop_sudo_keepalive() {
  if [ -n "$SUDO_KEEPALIVE_PID" ]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
  fi
}

start_sudo_keepalive() {
  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi

  log "Acquiring sudo credentials"
  sudo -v
  while true; do
    sudo -n true >/dev/null 2>&1 || exit 0
    sleep 60
  done &
  SUDO_KEEPALIVE_PID="$!"
  trap stop_sudo_keepalive EXIT
}

require_focal_amd64() {
  . /etc/os-release
  if [ "${VERSION_CODENAME:-}" != "focal" ]; then
    echo "This bootstrap must run on Ubuntu 20.04 focal; got ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo "This bootstrap currently supports amd64 only; got $(dpkg --print-architecture)" >&2
    exit 1
  fi
}

clean_ros_environment() {
  if [ -n "${CONDA_PREFIX:-}" ]; then
    echo "Warning: Conda is active. The script will force system Python/tool paths for the build." >&2
  fi
  export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  unset AMENT_PREFIX_PATH
  unset CMAKE_PREFIX_PATH
  unset COLCON_PREFIX_PATH
  unset ROS_DISTRO
  unset ROS_PYTHON_VERSION
  unset ROS_VERSION
}

configure_git_network() {
  if [ -z "$GIT_INSTEADOF_GITHUB_PREFIX" ]; then
    return 0
  fi
  log "Configuring git insteadOf for GitHub: $GIT_INSTEADOF_GITHUB_PREFIX"
  git config --global "url.$GIT_INSTEADOF_GITHUB_PREFIX.insteadOf" "https://github.com/"
}

install_apt_prerequisites() {
  log "Installing apt prerequisites"
  sudo apt-get update
  sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    locales \
    lsb-release \
    software-properties-common

  sudo locale-gen en_US en_US.UTF-8 >/dev/null
  sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
  export LANG=en_US.UTF-8

  sudo add-apt-repository -y universe >/dev/null

  if [ ! -f /usr/share/keyrings/ros-archive-keyring.gpg ]; then
    sudo curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      -o /usr/share/keyrings/ros-archive-keyring.gpg
  fi

  if [ ! -f /etc/apt/sources.list.d/ros2.list ]; then
    local codename
    codename="$(. /etc/os-release && printf '%s' "$UBUNTU_CODENAME")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $codename main" \
      | sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null
  fi

  sudo apt-get update
  sudo apt-get install -y \
    build-essential \
    git \
    libopencv-dev \
    patchelf \
    pkg-config \
    python3-colcon-common-extensions \
    python3-empy \
    python3-lark \
    python3-numpy \
    python3-pip \
    python3-pytest \
    python3-pytest-cov \
    python3-rosdep \
    python3-vcstool \
    python3-yaml \
    rsync \
    wget
  sudo apt-get install -y ros-dev-tools || true
}

install_python_prerequisites() {
  log "Installing user-level Python build prerequisites"
  /usr/bin/python3 -m pip install --user -U \
    'cmake>=3.22,<3.29' \
    'empy==3.3.4' \
    'flake8-blind-except' \
    'flake8-builtins' \
    'flake8-class-newline' \
    'flake8-comprehensions' \
    'flake8-deprecated' \
    'flake8-import-order' \
    'flake8-quotes' \
    'pytest>=5.3' \
    'pytest-repeat' \
    'pytest-rerunfailures'
  export PATH="$HOME/.local/bin:$PATH"
  cmake --version | head -n 1
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

resolve_repos_file() {
  local src="$1"
  local dst="$2"

  if [ -z "$GITHUB_URL_PREFIX" ]; then
    printf '%s\n' "$src"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  /usr/bin/python3 - "$src" "$dst" "$GITHUB_URL_PREFIX" <<'PY'
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
prefix = sys.argv[3]
data = src.read_text(encoding="utf-8")
data = data.replace("https://github.com/", prefix)
dst.write_text(data, encoding="utf-8")
PY
  printf '%s\n' "$dst"
}

update_rosdep_cache() {
  if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    sudo rosdep init || true
  fi
  configure_rosdep_network
  if rosdep update; then
    return 0
  fi

  echo "Warning: rosdep update reported a partial network failure; validating cache." >&2
  if rosdep resolve cmake --rosdistro humble --os=ubuntu:focal >/dev/null 2>&1; then
    echo "rosdep cache is usable; continuing after partial update failure." >&2
    return 0
  fi
  return 1
}

import_ros2_sources() {
  if [ "$CLEAN_BASE" = "1" ]; then
    log "Cleaning base ROS 2 workspace: $WORK_DIR"
    rm -rf "$BASE_SRC_DIR" "$BASE_PREFIX" "$BASE_BUILD_DIR" "$BASE_LOG_DIR" "$BASE_IMPORT_MARKER" "$BASE_BUILD_MARKER"
  fi

  mkdir -p "$BASE_SRC_DIR"
  if [ -f "$BASE_IMPORT_MARKER" ] && find "$BASE_SRC_DIR" -mindepth 1 -maxdepth 1 | read -r _; then
    log "Using existing ROS 2 source checkout: $BASE_SRC_DIR"
  else
    if find "$BASE_SRC_DIR" -mindepth 1 -maxdepth 1 | read -r _; then
      log "Incomplete ROS 2 source import found; cleaning $BASE_SRC_DIR before retry"
      rm -rf "$BASE_SRC_DIR"
      mkdir -p "$BASE_SRC_DIR"
    fi
    if [ ! -s "$ROS2_REPOS_FILE" ]; then
      log "Downloading ROS 2 Humble repos file: $ROS2_REPOS_URL"
      mkdir -p "$(dirname "$ROS2_REPOS_FILE")"
      curl -fsSL \
        --connect-timeout 10 \
        --max-time 60 \
        --retry 5 \
        --retry-delay 2 \
        "$ROS2_REPOS_URL" \
        -o "$ROS2_REPOS_FILE"
    fi
    local resolved_ros2_repos
    resolved_ros2_repos="$(resolve_repos_file "$ROS2_REPOS_FILE" "$RESOLVED_ROS2_REPOS_FILE")"
    if [ -n "$GITHUB_URL_PREFIX" ]; then
      log "Using GitHub URL prefix for source import: $GITHUB_URL_PREFIX"
    fi
    log "Importing ROS 2 Humble sources from $resolved_ros2_repos into $BASE_SRC_DIR"
    vcs import "$BASE_SRC_DIR" < "$resolved_ros2_repos"
    touch "$BASE_IMPORT_MARKER"
  fi

  vcs export --exact "$BASE_SRC_DIR" > "$WORK_DIR/ros2-source-lock.repos"
}

install_ros2_source_dependencies() {
  log "Installing ROS 2 source dependencies"
  update_rosdep_cache
  rosdep install \
    --from-paths "$BASE_SRC_DIR" \
    --ignore-src -y \
    --skip-keys "$ROSDEP_SKIP_KEYS" \
    --os=ubuntu:focal \
    --rosdistro humble
}

build_base_humble() {
  if [ -f "$BASE_BUILD_MARKER" ] && [ -f "$BASE_PREFIX/setup.bash" ] && [ "$REBUILD_BASE" != "1" ]; then
    log "Base Humble install space already exists: $BASE_PREFIX"
    log "Set REBUILD_BASE=1 or CLEAN_BASE=1 to rebuild it."
    return 0
  fi

  log "Building ROS 2 Humble base install space into $BASE_PREFIX"
  rm -rf "$BASE_PREFIX" "$BASE_BUILD_DIR" "$BASE_LOG_DIR" "$BASE_BUILD_MARKER"
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"
  export CMAKE_BUILD_PARALLEL_LEVEL

  colcon --log-base "$BASE_LOG_DIR" build \
    --merge-install \
    --base-paths "$BASE_SRC_DIR" \
    --install-base "$BASE_PREFIX" \
    --build-base "$BASE_BUILD_DIR" \
    --parallel-workers "$COLCON_PARALLEL_WORKERS" \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    $BASE_COLCON_CMAKE_ARGS \
    $BASE_COLCON_PACKAGES_ARGS
  touch "$BASE_BUILD_MARKER"
}

verify_base_humble() {
  log "Verifying base Humble install space"
  source_ros_setup "$BASE_PREFIX/setup.bash"
  ros2 pkg prefix rclcpp >/dev/null
  ros2 pkg prefix rviz2 >/dev/null
  ros2 pkg prefix rmw_cyclonedds_cpp >/dev/null
}

build_unified_artifacts() {
  log "Building third-party overlay and deploy artifacts"
  if [ ! -f "$PROFILE" ]; then
    echo "Missing third-party profile: $PROFILE" >&2
    exit 1
  fi
  local profile_for_build="$PROFILE"
  if [ -n "$GITHUB_URL_PREFIX" ]; then
    profile_for_build="$(resolve_repos_file "$PROFILE" "$WORK_DIR/third_party.resolved.repos")"
  fi

  PROFILE="$profile_for_build" \
  BASE_PREFIX="$BASE_PREFIX" \
  WORK_DIR="$UNIFIED_WORK_DIR" \
  PKG_VERSION="$PKG_VERSION" \
  INSTALL_PREFIX="$INSTALL_PREFIX" \
  BUILD_BASE="$BASE_BUILD_DIR" \
  ROSDEP_USE_MIRROR="$ROSDEP_USE_MIRROR" \
  ROSDEP_ROSDISTRO_MIRROR="$ROSDEP_ROSDISTRO_MIRROR" \
  ROSDEP_EXTRA_SOURCE_PATHS="$BASE_SRC_DIR" \
  ROSDEP_SKIP_KEYS="$ROSDEP_SKIP_KEYS" \
  COLCON_PACKAGES_ARGS="$THIRD_PARTY_COLCON_PACKAGES_ARGS" \
  COLCON_CMAKE_ARGS="$THIRD_PARTY_COLCON_CMAKE_ARGS" \
  "$REPO_ROOT/builder/build_unified_humble_env.sh"
}

install_generated_artifacts() {
  if [ "$INSTALL_AFTER_BUILD" != "1" ]; then
    log "INSTALL_AFTER_BUILD=0, not installing generated artifacts."
    return 0
  fi

  local artifacts="$UNIFIED_WORK_DIR/package_out/artifacts"
  local bundle_name="ros2-humble-focal-offline-bundle_${PKG_VERSION}_amd64"
  ARTIFACT_DIR="$artifacts" OUT_DIR="$artifacts/offline" BUNDLE_NAME="$bundle_name" \
    bash "$REPO_ROOT/builder/package/build_offline_humble_bundle.sh"
  log "Installing the generated development environment without clearing existing overlays"
  sudo bash "$artifacts/offline/$bundle_name/install.sh"
}

print_summary() {
  local artifacts="$UNIFIED_WORK_DIR/package_out/artifacts"
  cat <<EOF

Done.

Base source workspace:
  $WORK_DIR

Generated artifacts:
  $artifacts

Installed prefix:
  $INSTALL_PREFIX

Use:
  source $INSTALL_PREFIX/setup.bash

Third-party package list:
  $PROFILE

To evaluate new third-party packages, edit profiles/third_party.repos and run:
  PROFILE="\$PWD/profiles/third_party.repos" ./builder/bootstrap_humble_focal_env.sh

EOF
}

main() {
  require_focal_amd64
  clean_ros_environment
  configure_git_network
  start_sudo_keepalive
  install_apt_prerequisites
  install_python_prerequisites
  import_ros2_sources
  install_ros2_source_dependencies
  build_base_humble
  verify_base_humble
  build_unified_artifacts
  install_generated_artifacts
  print_summary
}

main "$@"
