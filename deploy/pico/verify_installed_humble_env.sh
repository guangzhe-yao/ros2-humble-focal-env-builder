#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/ros/humble}"

if [ ! -f "$INSTALL_PREFIX/setup.bash" ]; then
  echo "Missing $INSTALL_PREFIX/setup.bash" >&2
  exit 1
fi

set +u
# shellcheck disable=SC1090
source "$INSTALL_PREFIX/setup.bash"
set -u

echo "ROS prefix: $INSTALL_PREFIX"
echo "ROS_DISTRO=${ROS_DISTRO:-}"
echo "Package count: $(ros2 pkg list | wc -l)"
echo "Marker deb count: $(dpkg-query -W -f='${Package}\n' 'ros-humble-*' 2>/dev/null | wc -l)"

for pkg in rclcpp rviz2 std_msgs controller_manager joint_trajectory_controller; do
  prefix="$(ros2 pkg prefix "$pkg" 2>/dev/null || true)"
  if [ -n "$prefix" ]; then
    printf '%s -> %s\n' "$pkg" "$prefix"
  else
    printf '%s -> not installed\n' "$pkg"
  fi
done

if ros2 pkg prefix rmw_cyclonedds_cpp >/dev/null 2>&1; then
  echo "rmw_cyclonedds_cpp -> $(ros2 pkg prefix rmw_cyclonedds_cpp)"
else
  echo "rmw_cyclonedds_cpp -> not installed" >&2
  exit 1
fi

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-20}"
export ROS_LOCALHOST_ONLY="${ROS_LOCALHOST_ONLY:-0}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
if [ -z "${CYCLONEDDS_URI:-}" ] && [ -f /etc/ros/cyclonedds/pico-cyclonedds.xml ]; then
  export CYCLONEDDS_URI="file:///etc/ros/cyclonedds/pico-cyclonedds.xml"
fi

python3 - <<'PY'
import os
import rclpy

rclpy.init()
node = rclpy.create_node("verify_humble_cyclonedds")
print(
    "CycloneDDS node creation passed: "
    f"domain={os.environ.get('ROS_DOMAIN_ID', '')} "
    f"rmw={os.environ.get('RMW_IMPLEMENTATION', '')} "
    f"uri={os.environ.get('CYCLONEDDS_URI', '')}"
)
node.destroy_node()
rclpy.shutdown()
PY

if [ -f /opt/zj_humanoid/tools/ros2_link_test.py ]; then
  echo "ROS 2 link test tool -> /opt/zj_humanoid/tools/ros2_link_test.py"
fi

check_bash_completion() {
  if [ -z "${BASH_VERSION:-}" ]; then
    return 0
  fi

  if ! command -v register-python-argcomplete3 >/dev/null 2>&1 &&
      ! command -v register-python-argcomplete >/dev/null 2>&1; then
    echo "ERROR: python3-argcomplete is missing; ros2 tab completion will not work." >&2
    return 1
  fi

  if ! complete -p ros2 >/dev/null 2>&1 &&
      [ -f "$INSTALL_PREFIX/share/ros2cli/environment/ros2-argcomplete.bash" ]; then
    # shellcheck disable=SC1090
    source "$INSTALL_PREFIX/share/ros2cli/environment/ros2-argcomplete.bash"
  fi

  if complete -p ros2 >/dev/null 2>&1; then
    echo "ros2 bash completion -> registered"
  else
    echo "ERROR: ros2 bash completion is not registered after sourcing setup.bash." >&2
    return 1
  fi
}

check_optional_python_tools() {
  python3 - <<'PY'
import importlib

for module_name in ("argcomplete", "pygraphviz"):
    importlib.import_module(module_name)
    print(f"{module_name} -> import ok")
PY
}

check_rosdep_rules() {
  if ! command -v rosdep >/dev/null 2>&1; then
    echo "Warning: rosdep is not installed; skipping rosdep rule cache check." >&2
    return 0
  fi

  local missing=()
  local key
  for key in rclcpp std_msgs; do
    if rosdep resolve "$key" --rosdistro humble --os=ubuntu:focal >/dev/null 2>&1; then
      echo "rosdep rule $key -> ok"
    else
      missing+=("$key")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Warning: rosdep cache has no rule for: ${missing[*]}" >&2
    echo "Runtime ROS 2 is installed; update rosdep before building overlay workspaces with rosdep." >&2
  fi
}

check_overlay_build_tools() {
  if [ "${VERIFY_OVERLAY_BUILD_TOOLS:-0}" != "1" ]; then
    return 0
  fi

  local tool
  for tool in c++ cmake colcon rosdep; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "ERROR: overlay build tool is missing: $tool" >&2
      return 1
    fi
    printf '%s -> %s\n' "$tool" "$(command -v "$tool")"
  done

  local cmake_version
  cmake_version="$(cmake --version | awk '/version/ {print $3; exit}')"
  if ! dpkg --compare-versions "$cmake_version" ge 3.22; then
    echo "ERROR: CMake >= 3.22 is required for the packaged ros2_control overlay; got $cmake_version" >&2
    return 1
  fi
  echo "overlay CMake version -> $cmake_version"
}

check_bash_completion
check_optional_python_tools
check_rosdep_rules
check_overlay_build_tools

if ros2 pkg prefix ros2controlcli >/dev/null 2>&1; then
  ros2 control --help >/dev/null
fi

echo "Installed Humble environment smoke check passed."
