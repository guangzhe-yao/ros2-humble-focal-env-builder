# Pico 离线部署 ROS 2 Humble 前置环境

网络不稳定时，不建议每台 Pico 都重新拉 GitHub、源码编译 Humble。推荐流程是：

```text
一台网络较好的稳定 Pico 构建一次
  -> 生成离线 tar.gz
  -> 复制到其他 Pico
  -> 其他 Pico 离线安装
```

## 1. 在稳定 Pico 上生成离线包

稳定 Pico 已经跑通过源码构建后，会有：

```text
~/ros2_humble_unified/package_out/artifacts
```

注意：离线包需要使用当前仓库版本重新生成过的 `artifacts/`，因为新的
`install_ros2_humble.sh` 支持跳过联网 apt/rosdep 步骤。旧 artifacts 会被
`build_offline_humble_bundle.sh` 拒绝。

在仓库根目录执行：

```bash
cd /home/nav01/Public/ros2-humble-focal-env-builder

ARTIFACT_DIR=~/ros2_humble_unified/package_out/artifacts \
./packaging/build_offline_humble_bundle.sh
```

如果稳定 Pico 已经有 `~/ros2_humble_unified/install_deploy`，但 artifacts 是旧仓库
版本生成的，可以不重新拉源码、不重新编译，只重新出当前版本 artifacts 并同时
生成离线包：

```bash
cd /home/nav01/Public/ros2-humble-focal-env-builder
BUILD_OFFLINE_BUNDLE=1 ./packaging/repackage_existing_humble_artifacts.sh
```

生成结果类似：

```text
~/ros2_humble_unified/package_out/artifacts/offline/
  ros2-humble-focal-offline-bundle_<version>_amd64.tar.gz
```

如果希望源码构建完成后自动生成离线包：

```bash
BUILD_OFFLINE_BUNDLE=1 ./scripts/bootstrap_pico_humble_env.sh
```

## 2. 复制到新 Pico

```bash
scp ~/ros2_humble_unified/package_out/artifacts/offline/ros2-humble-focal-offline-bundle_*.tar.gz \
  nav01@192.168.217.66:~/Pictures/
```

## 3. 新 Pico 离线安装

```bash
cd ~/Pictures
tar -xzf ros2-humble-focal-offline-bundle_*.tar.gz
cd ros2-humble-focal-offline-bundle_*_amd64

sudo ./install_offline_humble_bundle.sh
source /etc/ros/source_ros2_humble_clean.bash
./artifacts/verify_installed_humble_env.sh
```

如果安装前目标机器自己的 apt/dpkg 状态已经断裂，安装器会先报错并提示修复。
这不是 ROS 2 包本身的问题，而是基础系统存在未满足依赖。先修复系统包状态：

```bash
sudo apt update
sudo apt --fix-broken install -y
sudo ./install_offline_humble_bundle.sh
```

如果这台机器允许安装器临时使用在线 apt 源自动修复，可以直接执行：

```bash
ALLOW_ONLINE_APT_REPAIR=1 sudo -E ./install_offline_humble_bundle.sh
```

如果安装成功后 source 时看到类似下面的旧构建路径提示：

```text
not found: "/home/nav01/ros2_humble/install_deploy/local_setup.bash"
```

说明当前离线包是旧版打包脚本生成的，`setup.*` 里带入了构建机 underlay
路径。临时修复当前机器：

```bash
sudo sed -i \
  '/COLCON_CURRENT_PREFIX="\/home\/nav01\/ros2_humble\/install_deploy"/,+1d' \
  /opt/ros/humble/setup.bash \
  /opt/ros/humble/setup.sh \
  /opt/ros/humble/setup.zsh

source /etc/ros/source_ros2_humble_clean.bash
./artifacts/verify_installed_humble_env.sh
```

重新用当前仓库打出的离线包不会再带这个路径。

如果目标机器上已经有旧环境，并确认要覆盖：

```bash
sudo ./install_offline_humble_bundle.sh
```

离线安装器默认会先清理旧的 `/opt/ros/humble`、`ros-humble-*` marker 和主
bundle 包，然后安装当前离线包，所以可以用于更新或修复不完整安装。若只想在
发现旧环境时失败而不是覆盖：

```bash
REINSTALL_EXISTING=0 sudo -E ./install_offline_humble_bundle.sh
```

## 4. 离线包里有什么

```text
artifacts/
  install_ros2_humble.sh
  verify_installed_humble_env.sh
  ros2-humble-focal-desktop-source_*.deb
  ros-humble-package-markers_*.tar.gz
  orin_pico_cyclonedds/
apt_debs/
  *.deb
install_offline_humble_bundle.sh
```

`artifacts/` 是源码构建后的 ROS 2 Humble 环境；`apt_debs/` 是目标 Pico
安装时需要的 Ubuntu 依赖包。目标 Pico 不再需要访问 GitHub，也不需要重新编译。

默认离线包只包含运行依赖。若你确实希望目标 Pico 后续也能离线编译 overlay，
可以在稳定 Pico 打包时加：

```bash
INCLUDE_DEV_DEPS=1 BUILD_OFFLINE_BUNDLE=1 ./packaging/repackage_existing_humble_artifacts.sh
```

如果希望任何 apt 依赖下载失败都直接让打包失败：

```bash
FAIL_ON_MISSING_APT_DEBS=1 BUILD_OFFLINE_BUNDLE=1 ./packaging/repackage_existing_humble_artifacts.sh
```
