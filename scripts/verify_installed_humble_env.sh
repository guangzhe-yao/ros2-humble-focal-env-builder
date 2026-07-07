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

rosdep resolve rclcpp --rosdistro humble --os=ubuntu:focal >/dev/null
rosdep resolve std_msgs --rosdistro humble --os=ubuntu:focal >/dev/null

if ros2 pkg prefix ros2controlcli >/dev/null 2>&1; then
  ros2 control --help >/dev/null
fi

echo "Installed Humble environment smoke check passed."
