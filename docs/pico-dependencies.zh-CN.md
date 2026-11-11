# Pico 依赖与 ROS 1 迁移

## 范围与判定

本轮只分析本地 Pico 项目：lowerlimb、lowerlimb-humble、robot_state_v1，
以及 navi_ros2_sdk 中的 lowerlimb、navi_robot_msgs、robot_nodes_cpp、robot_nodes_py。
不扫描 SDK 的 Orin 感知、导航、音频组件。用户确认默认不交付 Gazebo 仿真。

扫描 package.xml、CMake 的字面量 find_package、XML/Python launch 中的字面量包引用。
扫描工具不执行项目代码，不把目录名中带 humble 当作已完成迁移；动态引用和条件依赖仍需人工复核。
2026-11-11 扫描得到 18 个本地包名、40 项上游 ROS 2 引用、12 项 ROS 1 迁移项、
21 项系统/供应方/待确认名称，以及 ament_python 构建类型。
逐文件证据保存在本地 log/pico-project-dependencies-20261111.json，不将绝对路径报告作为部署配置。

上游来源按 ROS 的 [Humble rosdistro](https://github.com/ros/rosdistro/blob/master/humble/distribution.yaml)
核对，快照 blob 和 SHA256 在 profiles/ros-upstream.json。
“被 rosdistro 收录”不等于所有包均由 Open Robotics 开发，也不代表厂商 SDK 自动获得准入。
同名包若在本地工作区声明，优先标记 local_or_vendored，不自动当作可信上游实现。

## 默认交付

- 基础通信、常用消息：rclcpp/rclpy、std_msgs、sensor_msgs、geometry_msgs、std_srvs。
- 构建和消息生成：ament、colcon、rosidl、C/C++、CMake、Python/pip/venv 与系统开发库。
- 控制接口：ros2_control、controller_interface、controller_manager、hardware_interface、pluginlib。
- 模型与工具：TF2、robot_state_publisher、joint_state_publisher_gui、xacro、RViz2、rosbag2。
- 手柄：已有 joy/joy_linux；本轮增加 teleop_tools 上游仓库的 joy_teleop、teleop_tools_msgs、
  key_teleop、mouse_teleop、teleop_tools。保留上游仓库一致的源码版本，补入 python3-tk 系统依赖。

teleop_tools 固定在 [1.7.0 对应提交](https://github.com/ros-teleop/teleop_tools/tree/ac63b92477232d8fd73fa9db938ead6735c31971)。
该提交的 ROS package.xml 为 1.7.0，部分 Python setup.py 仍为 1.6.0；不擅自修改上游源码，
以实际源码提交、ROS 包版本和产物哈希追溯。安装检查只导入模块/类型支持，不启动手柄控制。

全量 ELF 检查另发现旧环境漏装 libdw1：libbackward.so、ros2_control_node、
wrench_transformer_node 均报告 libdw.so.1 未找到。本轮将 libdw1 加入显式运行根依赖；
打包遇到未解析动态库立即失败，断网验收检查所有 823 个 ELF 文件，不实际启动控制节点。

## 不属于本环境

legged_*、navi_robot_msgs、robot_nodes_*、robot_state、zj_robot、audio 等本地包，
以及它们的 URDF、mesh、参数、launch、消息和业务控制器，均由项目自己提供。
libbase_fsm 与 legged_base_fsm 的名称差异应由项目修正，不能伪造一个官方包补洞。
hand_interface、joy_manager、legged_nav3_hw、legged_nav3t_hw、legged_unitree_description 等
未找到对应本地声明或已核对上游来源的引用，保持待项目方确认，不自动下载同名仓库。

rtipc_runtime、uplimb_runtime、uplimb_interface 属于供应方接口；libonnxruntime、Pinocchio
不是 ROS 核心功能包，交由对应运行环境管理，不从本仓库安装 robotpkg 或供应方 SDK。
Eigen3/HDF5/PkgConfig/glog/yaml-cpp、libzmq3-dev、Python 工具属于系统依赖，不是 ROS 包。
其中通用开发项由 apt-development.txt/apt-runtime.txt 管理；cmake_clang_tools 是可选源码检查工具。
python3-catkin-pkg 是 ROS 包清单解析工具，ROS 2 构建也会使用；保留它不等于把 ROS 1/catkin 工程装进环境。

## ROS 1 对应关系

| ROS 1 | ROS 2 Humble | 迁移注意 |
| --- | --- | --- |
| catkin | ament_cmake / ament_cmake_python | 修改 CMake 与 package.xml；ament_python 是构建类型 |
| roscpp / rospy | rclcpp / rclpy | 节点、参数和通信 API 需要改写 |
| message_generation / message_runtime | rosidl_default_generators / rosidl_default_runtime | 使用 rosidl_generate_interfaces |
| actionlib | rclcpp_action / rclpy.action | action 接口不是直接替换类名 |
| roslaunch | launch / launch_ros / launch_xml | 旧 launch 不能原样视为 ROS 2 launch |
| rviz / rosbag | rviz2 / rosbag2 | 配置、插件及数据格式需适配 |
| nodelet | rclcpp_components | 改成组合节点 |
| tf | tf2 / tf2_ros / tf2_geometry_msgs | 修改变换 API |
| gazebo_ros_control | gazebo_ros2_control | 可选仿真，URDF/plugin 需要移植 |

机器可读对应关系在 profiles/ros1-migration.json；参考 [ROS 2 官方迁移指南源码](https://github.com/ros2/ros2_documentation/blob/humble/source/Contributing/Migration-Guide.rst)。
仿真候选在 pico-simulation-packages.txt，未纳入默认离线保证。安装对应包并不意味着客户源码已经迁移。
不把 ros1_bridge 默认装入纯 ROS 2 基础包；它涉及双环境及自定义接口匹配，应另行按需交付。

## 实机升级边界

2026-11-11 只读检查指定 Pico：Ubuntu 20.04.6 amd64，同时存在 Noetic 和 Humble。
旧基础 DEB 0.3.1+202608241111 拥有 navi_robot_msgs/robot_nodes_py 的真实文件，
且有机器人相关进程运行。新安装器拒绝这种升级，防止 dpkg 自动清除旧包中的业务文件。
本轮不迁移业务包、不停止机器人服务；实机上的安装验证在隔离、断网 Focal 容器进行。

对旧 20261015dev1 二进制进一步检查还发现，虽然 ament 索引不含业务包，
include/zj_humanoid/ 和 lib/python3.8/site-packages/zj_humanoid/ 仍有业务消息残留。
新打包入口增加未登记文件检查并拒绝此类输入。本轮只在新的构建副本中明确排除这两棵目录，
保留旧二进制不动；来源记录标明这一处理，不将旧包的清单验收当成完整文件边界证明。

随后用户明确授权清退实机这两个业务包并要求不备份。本次一次性维护仅移除对应 marker，
再由 dpkg 升级基础 DEB，删除旧基础包所属、但新包不再提供的业务文件；不清空前缀，
不改开发者源码工作区。安装器仍保留默认拒绝混装升级的保护，不承担业务包迁移或卸载。
实机安装时另外发现，主动请求升级所有系统根依赖会触发 systemd/udev 版本冲突及连带卸载；
dev3 改为仅显式请求缺失的系统根依赖，实际版本约束仍交由 APT 求解。
最终模拟仅涉及两项授权移除，没有其他软件卸载或已安装系统包升级。
