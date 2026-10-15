# Humble Focal 离线部署

适用：Ubuntu 20.04 / amd64。基础环境版本 `0.3.2+20261015`。
包含 Humble 基础环境、ROS 包索引、robot-state、lowerlimb、指定上肢包、供应方运行库和 Ubuntu 依赖。

## 安装

在目标机器解压整个压缩包，保持目录结构，不要只复制业务 DEB。

```bash
sha256sum -c robot-humble-focal-offline-20261015-amd64.tar.gz.sha256
tar -xzf robot-humble-focal-offline-20261015-amd64.tar.gz
cd robot-humble-focal-offline-20261015-amd64
bash install.sh --check
sudo bash install.sh --install
bash verify-installation.sh
source /opt/ros/humble/setup.bash
```

默认只检查。安装脚本只使用包内的本地 apt 源，不访问在线软件源；校验文件后模拟安装，拒绝删除不相关的软件包，也不允许自动降级。旧基础环境中误带的两个业务 marker 会被替换，其他业务文件由独立 DEB 管理。

请使用本目录的 `install.sh`，不要使用 `artifacts/` 中旧的基础环境单独安装入口。安装前应停止用户业务并备份系统、SDK 配置和标定 YAML。安装本身不执行机器人控制、标零或关机命令；系统依赖的软件包安装钩子仍由 apt/dpkg 按标准机制处理。

## 查看版本与依赖

```bash
apt list --installed 'ros-humble-*' 'zj-humanoid-*' ros2-humble-focal-desktop-source
apt-cache depends zj-humanoid-robot-platform-deps
apt-cache depends zj-humanoid-ros-humble-naviai-robot
dpkg --audit
```

`apt list` 列出版本，不显示依赖图；依赖通过 `apt-cache depends` 查看。供应方原始 DEB 保持原样，其缺失的运行依赖通过 `zj-humanoid-robot-platform-deps` 声明。

## 边界

- 不包含系统镜像、Xenomai 内核或机型 SDK。Xenomai 3.1.4 用户态不能替代匹配的 Cobalt 内核。
- 不配置电机使能、系统自启动、实时 CPU 隔离、sudo 权限或实机标定数据。
- 指定 RTIPC 1.4.4focal、uplimb runtime 1.4.3focal；上肢 interface/msg 为用户提供的 featwat+533.c9959d2focal。
- 当前 I2 SDK 缺少 `robotfull2robot.py`，保存 YAML 的返回值处理也存在缺陷。标零必须先与 SDK 维护方完成转换、持久化校验、备份恢复和控制器退出的联调。
- 本包仅适用于 Focal/Humble。Jazzy 需要对应平台重新构建和验证，不能直接复用这些二进制。
- `verify-installation.sh` 只检查包、接口导入和动态库，不启动控制节点，也不代表运动、急停、SDK 切换或实时性能验收。
