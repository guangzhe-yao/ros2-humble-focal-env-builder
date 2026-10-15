# ROS 2 Humble Focal 开发环境构建器

[English](README.md)

本仓库只负责 Ubuntu 20.04 amd64 的 ROS 2 Humble 开发环境。

## 职责边界

- 提供 ROS 2 上游包、消息生成、ros2_control、RViz2。
- 提供 C/C++、CMake、colcon、Python/pip/venv、vcstool 和通用开发依赖。
- 不包含 robot-state、lowerlimb、上肢接口等自定义业务包。
- runtime、SDK、Xenomai 用户态及内核由系统提供，本构建器不安装、不修改。
- 上游 `robot_state_publisher` 等通用 ROS 包仍然保留，不属于自定义 robot-state。
- 不清空 ROS 安装目录，不卸载业务 DEB，不启动机器人服务。

## 直接安装

解压完整离线包，在解压目录执行：

```bash
sudo bash install.sh
source /opt/ros/humble/setup.bash
```

无需单独运行 check 或验证脚本。安装器自动校验文件后从包内 apt 源直接安装。
也可将整个 `release/pico/` 复制到目标机，执行其中的 `sudo bash install.sh`。
详见[离线安装说明](deploy/pico/README_OFFLINE.zh-CN.md)。

## 发布

```bash
SOURCE_PREFIX=/path/to/clean/humble/install bash builder/package_installed_pico.sh
```

发布源必须是干净的 Humble underlay。构建器根据
`profiles/humble-environment-packages.txt` 检查包边界；
发现混入业务 overlay 时直接拒绝出包，不猜测如何删除共享库。
新增上游通用包时，应同时更新白名单和源码锁定清单。

详见[构建与发布](docs/build-release-deploy.zh-CN.md)。
发布前内部测试保留，包括断网安装、C++ 编译和自定义消息生成，
但不会作为用户安装流程中的额外步骤。
