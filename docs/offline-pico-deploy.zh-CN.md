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

如果目标机器上已经有旧环境，并确认要覆盖：

```bash
FORCE_REINSTALL=1 sudo -E ./install_offline_humble_bundle.sh
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
