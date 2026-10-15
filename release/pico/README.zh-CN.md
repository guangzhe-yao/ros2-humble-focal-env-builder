# Humble 开发环境离线发布

本目录仅保留最新开发环境发布包及校验文件，不包含业务模块交付包。

将整个目录复制到 Ubuntu 20.04 amd64 机器，直接执行：

```bash
sudo bash install.sh
source /opt/ros/humble/setup.bash
```

也可以只复制版本化 tar.gz 及其 SHA256 文件，解压后执行包内的
`sudo bash install.sh`。安装器不提供 check 模式，不联网，
不安装自定义业务包、vendor runtime、SDK 或 Xenomai。

最新基础环境：`0.3.3+20261015`。
发布文件：`ros2-humble-focal-offline-bundle_20261015dev1_amd64.tar.gz`。

约 330 MiB，包含 399 个通用 ROS 包及开发依赖，共 1029 个 DEB。
已通过全新 Ubuntu 20.04 断网安装、C++ 编译、自定义消息生成和 Python
类型支持测试。文件校验值和验证范围见 `humble-development-20261015.json`。
二进制发布文件保存在本目录，不提交到 Git；仓库保存构建脚本和发布清单。
