# controller_interface Smoke Test

This package verifies that a deployed unified Humble focal environment can build
and use a custom `controller_interface::ControllerInterface` plugin.

The test controller:

- derives from `controller_interface::ControllerInterface`;
- uses `auto_declare<double>("gain", 2.0)`;
- returns `NONE` command and state interface configurations;
- implements `update()` and returns `controller_interface::return_type::OK`;
- exports itself through pluginlib.

Run on a target machine after installing the unified bundle:

```bash
rm -rf ~/controller_interface_custom_test
mkdir -p ~/controller_interface_custom_test/src
cp -a tests/controller_interface_smoke ~/controller_interface_custom_test/src/

cd ~/controller_interface_custom_test
source /opt/ros/humble/setup.bash
rosdep check --from-paths src --ignore-src --rosdistro humble --os=ubuntu:focal
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
ros2 run controller_interface_smoke controller_interface_smoke_test
```

Expected output:

```text
Loaded plugin: controller_interface_smoke/SmokeController
Controller node: smoke_controller
auto_declare gain: 2
Interface configuration: NONE/NONE
update() result: OK
```

