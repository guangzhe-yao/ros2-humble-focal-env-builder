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

安装器安装 apt 依赖时使用包内本地 apt 仓库，并默认 `--no-upgrade`：只补缺失
依赖，不升级目标机器已有的系统包。如果 apt 计划删除任何系统包，安装器会直接
拒绝继续执行。

如果拒绝日志里大量出现 `Remv ros-noetic-*` 或 `Remv zj-humanoid-ros-noetic-*`，
不要强制安装。这说明某个离线依赖会破坏目标机已有 ROS 1/Noetic 业务环境。
运行版离线包不会默认安装 `python3-rosdep2`，因为它不是 ROS 2 运行时必需项，
并且在保留 Noetic 的机器上容易触发这类 apt 删除计划。需要在目标机上编译
overlay 时，再按该机器的 ROS 1/ROS 2 共存策略单独处理 rosdep。

如果 `ros2 node list` 或验证脚本报类似：

```text
ImportError: libspdlog.so.1: cannot open shared object file
```

说明当前离线包漏了运行时系统库，不是 source 命令的问题。不要在无网络目标机上
临时乱改系统源，直接换用重新打包后的离线包。定档包会把 `libspdlog1`、
`python3-packaging`、`libyaml-cpp0.6`、`libtinyxml2-6a`、OpenCV/RViz/joy
等运行依赖都放进 `apt_debs/`，安装时仍然遵守 `--no-upgrade`。

如果 `ros2 no<Tab>`、`ros2 topic <Tab>` 没有补齐，通常是缺少
`python3-argcomplete`，或安装后当前 shell 没有重新 source。定档包已包含
`python3-argcomplete` 和 `bash-completion`；安装后重新执行：

```bash
source /etc/ros/source_ros2_humble_clean.bash
complete -p ros2
```

能看到 `complete ... ros2` 就说明补齐已经注册。

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

打包器会同时读取 `runtime-deps.txt` 和主 Humble deb 的 `Depends` / `Pre-Depends`
字段。即使复用了旧 artifacts 且文本依赖清单已经过期，离线包也会按 deb 的实际
声明补齐依赖，避免安装到 `dpkg` 阶段才发现缺包。

默认离线包只包含运行依赖。若你确实希望目标 Pico 后续也能离线编译 overlay，
可以在稳定 Pico 打包时加：

```bash
INCLUDE_DEV_DEPS=1 BUILD_OFFLINE_BUNDLE=1 ./packaging/repackage_existing_humble_artifacts.sh
```

如果目标 Pico 要直接编译/调试 `navi_ros2_sdk/src/robot`、`src/lowerlimb`、
`src/upperlimb`，建议同时把这些 overlay 的公共 apt 依赖打进离线包：

```bash
INCLUDE_DEV_DEPS=1 \
EXTRA_APT_ROOT_DEPS_FILE="$PWD/profiles/pico_robot_overlay_apt_deps.txt" \
BUILD_OFFLINE_BUNDLE=1 \
./packaging/repackage_existing_humble_artifacts.sh
```

`rtipc_runtime`、`uplimb_runtime` 以及腿部控制相关的本地/vendor 包如果不是来自
公共 apt 源，需要把对应 `.deb` 放到一个目录，再在打包时额外传入：

```bash
EXTRA_APT_DEBS_DIR=/path/to/local-debs \
EXTRA_APT_ROOT_DEPS_FILE="$PWD/profiles/pico_robot_overlay_apt_deps.txt:/path/to/vendor-deps.txt" \
BUILD_OFFLINE_BUNDLE=1 \
./packaging/repackage_existing_humble_artifacts.sh
```

`EXTRA_APT_ROOT_DEPS_FILE` 支持用冒号分隔多个依赖清单。`EXTRA_APT_DEBS_DIR`
也支持用冒号分隔多个本地 deb 目录；打包脚本会把这些 deb 复制进离线 apt 仓库，
并自动读取 deb 里的 `Package`、`Depends`、`Pre-Depends` 字段，尽量把 vendor
deb 的公共系统依赖也一起补进离线包。仓库里提供了
`profiles/pico_robot_vendor_apt_deps.example.txt` 作为 vendor 包名模板。
详细依赖拆分见 `docs/navi-ros2-sdk-pico-humble-deps.zh-CN.md`。

注意：为避免破坏已有 Noetic 环境，默认 dev 依赖也不再把 rosdep 打进离线包。
overlay 编译可以先使用已安装的 ROS 2 环境和 colcon；确实需要 `rosdep install`
时，建议在专门的构建机上处理，或先确认安装 rosdep 不会导致 `ros-noetic-*`
包被 apt 删除。

如果希望任何 apt 依赖下载失败都直接让打包失败：

```bash
FAIL_ON_MISSING_APT_DEBS=1 BUILD_OFFLINE_BUNDLE=1 ./packaging/repackage_existing_humble_artifacts.sh
```

完整 desktop/RViz 产物还会依赖 `libignition-math6`。打包脚本会在构建离线包时
从 OSRF Gazebo focal 源下载这个 deb 放进离线包；这只影响打包机下载产物，不会
在目标 Pico 上新增在线 apt 源。
