#!/usr/bin/env bash
set -Eeuo pipefail
# Run after install in a disposable Focal container; never starts ROS nodes.
. /etc/os-release
[[ "$VERSION_CODENAME/$(dpkg --print-architecture)" == focal/amd64 ]]
[[ -z "$(dpkg --audit)" ]]
unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH CMAKE_PREFIX_PATH PYTHONPATH LD_LIBRARY_PATH
set +u
source /opt/ros/humble/setup.bash
set -u
export ROS_LOCALHOST_ONLY=1 ROS_DOMAIN_ID=229
for package in navi_robot_msgs robot_nodes naviai_robot legged_messages uplimb_interface upperlimb_msgs; do
  [[ "$(ros2 pkg prefix "$package")" == /opt/ros/humble ]]
done
python3 - <<'PY'
import rclpy
from navi_robot_msgs.msg import RobotState
from navi_robot_msgs.srv import SetZero
from legged_messages.msg import MotorInfo
from legged_messages.srv import GetVersion
from rosidl_generator_py import import_type_support
for package in ('navi_robot_msgs', 'legged_messages', 'upperlimb_msgs'):
    import_type_support(package)
print('Python ROS interfaces and native type support import successfully')
PY
ros2 interface show navi_robot_msgs/srv/SetZero
ros2 interface show legged_messages/srv/GetVersion
dpkg-query -S /opt/ros/humble/share/navi_robot_msgs/package.xml | grep '^zj-humanoid-ros-humble-navi-robot-msgs:'
dpkg-query -S /opt/ros/humble/share/robot_nodes/package.xml | grep '^zj-humanoid-ros-humble-robot-nodes:'
for binary in /opt/ros/humble/lib/robot_nodes/robot_runtime \
              /opt/ros/humble/lib/naviai_robot/naviai_robot_node \
              /opt/ros/humble/lib/liblegged_nav2_hw.so \
              /opt/ros/humble/lib/liblegged_rl_controllers.so; do
  [[ -f "$binary" ]] || { echo "Missing binary: $binary" >&2; exit 1; }
  dependencies="$(ldd "$binary")"
  if [[ "$dependencies" == *'not found'* ]]; then
    printf '%s\n%s\n' "$binary" "$dependencies" >&2
    exit 1
  fi
done
dpkg-query -W -f='${Package}\t${Version}\n' ros2-humble-focal-desktop-source 'zj-humanoid-*'
echo 'Robot delivery package/import/linkage checks passed; no control nodes started.'
