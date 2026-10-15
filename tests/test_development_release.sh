#!/usr/bin/env bash
set -Eeuo pipefail
# Maintainer acceptance test, run only in a disposable offline container.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -z "$(dpkg --audit)" ]]
for path in /opt/zj_humanoid /opt/openrobots /usr/xenomai; do
  [[ ! -e "$path" ]] || { echo "Unexpected vendor payload: $path" >&2; exit 1; }
done
unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH CMAKE_PREFIX_PATH PYTHONPATH LD_LIBRARY_PATH CYCLONEDDS_URI
set +u
source /opt/ros/humble/setup.bash
set -u
export ROS_LOCALHOST_ONLY=1 ROS_DOMAIN_ID=230
diff -u "$REPO/profiles/humble-environment-packages.txt" <(ros2 pkg list | sort -u)
python3 -c 'import rclpy; rclpy.init(); node = rclpy.create_node("humble_python_smoke"); node.destroy_node(); rclpy.shutdown()'
dependencies="$(ldd /opt/ros/humble/lib/rviz2/rviz2)"
[[ "$dependencies" != *'not found'* ]] || { printf '%s\n' "$dependencies" >&2; exit 1; }
for tool in c++ cmake colcon vcs pip3; do command -v "$tool"; done
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$REPO/tests/fixtures/development" "$work/src"
cd "$work"
colcon build --executor sequential --cmake-args -DCMAKE_BUILD_TYPE=Release
colcon test --executor sequential
colcon test-result --verbose
set +u
source install/setup.bash
set -u
python3 -c 'from humble_dev_interfaces.msg import Value; from rosidl_generator_py import import_type_support; import_type_support("humble_dev_interfaces"); assert Value(value="ok").value == "ok"'
ros2 run humble_dev_smoke dev_smoke
echo 'Offline C++ build, custom interface generation, Python import and execution passed.'
