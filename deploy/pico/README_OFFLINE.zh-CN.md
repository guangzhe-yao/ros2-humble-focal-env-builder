# Humble 开发环境离线安装

仅适用于 Ubuntu 20.04 / amd64，提供源码构建的 ROS 2 Humble 环境与开发依赖。

解压完整发布包，进入目录后直接执行：

```bash
sudo bash install.sh
source /opt/ros/humble/setup.bash
```

包含 ROS 2 上游包、消息生成工具、ros2_control、RViz2、C/C++ 编译工具、
CMake、colcon、Python/pip/venv、vcstool，以及通用开发库。
不包含 robot-state、lowerlimb、上肢接口等自定义业务包，
也不包含供应方 runtime、机器人 SDK、Xenomai 用户态或内核。
使用这些业务模块时，应从对应模块仓库单独构建或安装其交付包。

安装不需要联网，不提供单独的 check 模式；完整性校验由安装器自动执行。
使用包内私有 apt 源，不改写系统软件源，不清空 /opt/ros/humble，
不启动 ROS 节点，不安装机器人自启动服务，不卸载已安装的业务 DEB。
升级时只清理旧基础环境误带的两个空业务 marker。

ros-humble-* 是对应真实 ROS 内容的 apt 元数据包，依赖基础环境的精确版本；
installed,local 表示通过本地 DEB 安装，属于正常状态。
apt list 列出包及版本，apt-cache depends 显示依赖关系。

rosdep 在线索引、项目专用依赖和外部源码不是任意项目的全离线保证。
为避免与已有 Noetic 的 rosdep 包冲突，本环境不强制安装或更新 rosdep。
已知依赖已就绪的 ament/colcon 工程可直接离线编译。
