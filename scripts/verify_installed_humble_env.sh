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
  if ros2 pkg list | grep -qx "$pkg"; then
    printf '%s -> %s\n' "$pkg" "$(ros2 pkg prefix "$pkg")"
  else
    printf '%s -> not installed\n' "$pkg"
  fi
done

rosdep resolve rclcpp --rosdistro humble --os=ubuntu:focal >/dev/null
rosdep resolve std_msgs --rosdistro humble --os=ubuntu:focal >/dev/null

if ros2 pkg list | grep -qx ros2controlcli; then
  ros2 control --help >/dev/null
fi

echo "Installed Humble environment smoke check passed."
