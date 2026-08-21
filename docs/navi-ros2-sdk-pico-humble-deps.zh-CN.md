# navi_ros2_sdk Pico Humble 依赖清单

本文记录 `navi_ros2_sdk/src/robot`、`src/lowerlimb`、`src/upperlimb` 在
Ubuntu 20.04 amd64 Pico 上编译/调试时，相对 ROS 2 Humble 基础运行包还需要的
系统依赖。

## robot

Pico 核心 robot 闭环建议构建：

```bash
colcon build --symlink-install --packages-up-to robot_nodes_cpp robot_nodes_py
```

这条链路需要的 ROS 包已在基础 Humble 离线包中覆盖：

- `rclcpp`、`rclcpp_components`、`class_loader`
- `std_srvs`、`diagnostic_msgs`、`diagnostic_updater`、`diagnostic_aggregator`
- `sensor_msgs`、`std_msgs`
- `launch`、`launch_ros`、`ament_index_python`
- `rosidl_default_generators`、`rosidl_default_runtime`

额外本地/vendor 依赖：

- 公共 apt 开发包：`libspdlog-dev`、`libfmt-dev`、`libyaml-cpp-dev`。
  其中 `libspdlog-dev`/`libfmt-dev` 是在目标机上编译 `rclcpp` overlay 时需要的
  CMake 配置包；运行版 Humble 基础包只需要运行库。
- `rtipc_runtime`，通常由 `zj-humanoid-rtipc-runtime` deb 提供。

`navi_ros2_sdk` 的 Pico robot 2.0 交付当前锁定：

- 下载地址：`http://10.51.33.211:10000/chfs/shared/modules/rtipc_runtime/release/zj-humanoid-rtipc-runtime_1.4.2focal_amd64.deb`
- Debian 版本：`1.4.2focal`
- SHA-256：`ff6653f8725bcb38a3e569bf7daedd4e67da4981ce66f10ff6b979cdef5b2135`

该 vendor deb 属于业务 overlay 依赖，不应编进通用 Humble base。需要离线构建
Pico robot 时将它放入 `EXTRA_APT_DEBS_DIR`，或使用 `navi_ros2_sdk` 自身的
`pico-robot-common-deb`。本次 Pico 范围仅包含共享 `navi_robot_msgs`、
`robot_nodes_cpp` 和 `robot_nodes_py`；不把 Orin 或上下肢业务包并入基础环境。

`src/robot/system_monitor/autoware_system_monitor` 依赖 Autoware 组件
`autoware_cmake`、`autoware_utils`、`autoware_lint_common`，不属于 Pico 核心
robot 闭环；不要默认纳入空 Pico 的 robot 编译链路。

## lowerlimb

源码包已声明或 CMake 直接使用：

- ROS 包：`rclcpp`、`rclpy`、`hardware_interface`、`pluginlib`、`joy`、
  `geometry_msgs`、`sensor_msgs`、`std_msgs`、`builtin_interfaces`、`tf2`、
  `rclcpp_lifecycle`。
- 公共 apt 包：`libgoogle-glog-dev`、`libeigen3-dev`、`libzmq3-dev`、
  `libhdf5-dev`。
- 本地/vendor 包：`rtipc_runtime`、`uplimb_runtime`、`legged_rl_controllers`、
  `legged_nav_fsm`、`libbase_fsm`、`libonnxruntime`、`pinocchio`。

其中公共 apt 包已加入 `profiles/pico_robot_overlay_apt_deps.txt`。本地/vendor
包需要把对应 `.deb` 放进 `EXTRA_APT_DEBS_DIR` 后重新打开发版离线包。

## upperlimb

源码包已声明或 CMake 直接使用：

- ROS 包：`rclcpp`、`rclcpp_components`、`rclcpp_lifecycle`、`lifecycle_msgs`、
  `sensor_msgs`、`std_srvs`、`std_msgs`、`geometry_msgs`、`action_msgs`。
- 公共 apt 包：`pkg-config`、`libhdf5-dev`、`libzmq3-dev`、`libyaml-cpp-dev`。
- 本地/vendor 包：`rtipc_runtime`、`uplimb_runtime`。

公共 apt 包已加入 `profiles/pico_robot_overlay_apt_deps.txt`。本地/vendor 包同样
通过 `EXTRA_APT_DEBS_DIR` 纳入离线包。

## 重新打开发版离线包

在稳定构建 Pico 上执行：

```bash
cd /home/nav01/Public/ros2-humble-focal-env-builder
INCLUDE_DEV_DEPS=1 \
EXTRA_APT_ROOT_DEPS_FILE="$PWD/profiles/pico_robot_overlay_apt_deps.txt" \
EXTRA_APT_DEBS_DIR=/path/to/vendor-debs \
BUILD_OFFLINE_BUNDLE=1 \
./packaging/repackage_existing_humble_artifacts.sh
```

`EXTRA_APT_DEBS_DIR` 支持用冒号分隔多个 deb 目录；打包脚本会自动读取这些 deb
里的 `Package`、`Depends`、`Pre-Depends` 字段。
