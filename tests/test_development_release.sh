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
python3 - <<'PY'
import os
from pathlib import Path
import subprocess
from concurrent.futures import ThreadPoolExecutor
files = []
for path in Path('/opt/ros/humble').rglob('*'):
    if path.is_file():
        with path.open('rb') as stream:
            if stream.read(4) == b'\x7fELF':
                files.append(path)
env = dict(os.environ, LD_LIBRARY_PATH=':'.join(sorted({str(path.parent) for path in files})))
def check(path):
    result = subprocess.run(['ldd', str(path)], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return [str(path) + ': ' + line.strip() for line in result.stdout.splitlines() if 'not found' in line]
with ThreadPoolExecutor(max_workers=2) as workers:
    missing = [line for result in workers.map(check, files) for line in result]
assert not missing, '\n'.join(missing)
print('ELF dependencies resolved:', len(files))
PY
python3 "$REPO/builder/package/validate_environment.py" /opt/ros/humble \
  --allowlist "$REPO/profiles/humble-environment-packages.txt" \
  --required "$REPO/profiles/pico-ros-packages.txt" \
  --excluded "$REPO/profiles/excluded-components.txt"
diff -u "$REPO/profiles/humble-environment-packages.txt" <(ros2 pkg list | sort -u)
python3 - <<'PY'
import importlib
import ctypes
import os
from ament_index_python.packages import get_package_prefix
for package in ('joy', 'joy_teleop', 'teleop_tools_msgs', 'controller_interface', 'hardware_interface'):
    assert get_package_prefix(package) == '/opt/ros/humble', package
importlib.import_module('joy_teleop.joy_teleop')
from teleop_tools_msgs.action import Increment
from rosidl_generator_py import import_type_support
import_type_support('teleop_tools_msgs')
assert Increment.Goal(increment_by=[1]).increment_by[0] == 1
# OGRE's plugins.cfg loads PCZ globally before its dependent OctreeZone plugin.
plugin_dir = '/opt/ros/humble/opt/rviz_ogre_vendor/lib/OGRE/'
manager = ctypes.CDLL(plugin_dir + 'Plugin_PCZSceneManager.so', mode=os.RTLD_GLOBAL)
zone = ctypes.CDLL(plugin_dir + 'Plugin_OctreeZone.so')
print('OGRE dependent plugin loading passed with the sourced environment')
PY
python3 -c 'import rclpy; rclpy.init(); node = rclpy.create_node("humble_python_smoke"); node.destroy_node(); rclpy.shutdown()'
dependencies="$(ldd /opt/ros/humble/lib/rviz2/rviz2)"
[[ "$dependencies" != *'not found'* ]] || { printf '%s\n' "$dependencies" >&2; exit 1; }
for tool in c++ cmake colcon vcs pip3; do command -v "$tool"; done
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$REPO/tests/fixtures/development" "$work/src"
cp -r "$REPO/tests/controller_interface_smoke" "$work/src/"
cd "$work"
colcon build --executor sequential --cmake-args -DCMAKE_BUILD_TYPE=Release
colcon test --executor sequential
colcon test-result --verbose
set +u
source install/setup.bash
set -u
python3 -c 'from humble_dev_interfaces.msg import Value; from rosidl_generator_py import import_type_support; import_type_support("humble_dev_interfaces"); assert Value(value="ok").value == "ok"'
ros2 run humble_dev_smoke dev_smoke
ros2 run controller_interface_smoke controller_interface_smoke_test
echo 'Offline C++ build, custom interface generation, Python import and execution passed.'
