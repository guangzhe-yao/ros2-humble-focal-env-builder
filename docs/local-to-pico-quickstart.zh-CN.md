# Pico 从 0 源码安装 ROS 2 Humble 前置环境

这份文档只讲一件事：

> 一台新的 Ubuntu 20.04 amd64 Pico，当前没有 Humble，如何根据本仓库从源码
> 拉取、构建、打包并安装 `/opt/ros/humble`。

## 先记住结论

Pico 可以直接跑本仓库，但入口不是 `build_unified_humble_env.sh`。

新 Pico 从 0 安装的入口是：

```bash
./scripts/bootstrap_pico_humble_env.sh
```

这个脚本会按顺序完成：

```text
安装构建工具
  -> 根据 profiles/ros2_humble.repos 拉取 ROS 2 Humble 官方源码
  -> 用 profiles/third_party.lock.repos 拉取第三方源码
  -> 构建基础 Humble install space
  -> 合入第三方包
  -> 生成 artifacts
  -> 安装到 /opt/ros/humble
  -> 安装 Pico CycloneDDS 配置
  -> 执行安装后验证
```

## 1. 在 Pico 上拿到仓库

登录 Pico 后：

```bash
cd /home/nav01/Public
git clone https://github.com/guangzhe-yao/ros2-humble-focal-env-builder.git
cd ros2-humble-focal-env-builder
```

如果 Pico 不能访问 GitHub，可以先从本地开发机同步当前工作区到 Pico：

```bash
rsync -a --delete \
  --exclude .git \
  ./ nav01@192.168.217.66:/home/nav01/Public/ros2-humble-focal-env-builder/
```

关键点：以后正式部署建议走 Git tag 或 release artifact；开发调试阶段可以
用 `rsync` 同步未提交的脚本。

## 2. 第三方包在哪里配置

ROS 2 Humble 基础源码清单在：

```text
profiles/ros2_humble.repos
```

一般不要改它。它对应上游 Humble 的 `ros2.repos`。

新增或调整第三方 ROS 2 包，改这个文件：

```text
profiles/third_party.repos
```

正式稳定构建默认使用锁定版本：

```text
profiles/third_party.lock.repos
```

所以默认命令会用 `third_party.lock.repos`。如果你正在试新包，运行时显式指定：

```bash
PROFILE="$PWD/profiles/third_party.repos" \
./scripts/bootstrap_humble_focal_env.sh
```

试通以后，把生成的锁定清单保存回仓库：

```bash
cp ~/ros2_humble_unified/package_out/source-lock.repos \
  profiles/third_party.lock.repos
```

## 3. 在 Pico 上从 0 构建并安装

建议放在 `tmux` 里跑，因为完整源码构建会很久：

```bash
tmux new -s humble_bootstrap
```

然后执行：

```bash
cd /home/nav01/Public/ros2-humble-focal-env-builder

./scripts/bootstrap_pico_humble_env.sh
```

这个 Pico 入口脚本已经内置了当前实机验证过的默认值：

```bash
GIT_INSTEADOF_GITHUB_PREFIX=https://gh-proxy.com/https://github.com/
COLCON_PARALLEL_WORKERS=2
CMAKE_BUILD_PARALLEL_LEVEL=2
```

所以平时不用手动输入这三行。需要临时覆盖时，再在命令前显式传环境变量。

如果前一次源码拉取只完成了一部分，想清掉后重新拉：

```bash
CLEAN_BASE=1 ./scripts/bootstrap_pico_humble_env.sh
```

如果日志里出现 `destination path '.' already exists and is not an empty
directory`，说明上一次 `vcs import` 中断后留下了半截源码目录。新版脚本会在
没有导入完成标记时自动清理 `~/ros2_humble/src` 后重新拉取；老脚本可直接用
上面的 `CLEAN_BASE=1` 重跑。

默认输出位置：

```text
~/ros2_humble
~/ros2_humble_unified
~/ros2_humble_unified/package_out/artifacts
/opt/ros/humble
```

默认会直接安装到：

```text
/opt/ros/humble
```

如果只想构建和打包，不想安装：

```bash
INSTALL_AFTER_BUILD=0 ./scripts/bootstrap_humble_focal_env.sh
```

如果机器上已有旧的 `/opt/ros/humble`，并确认要覆盖：

```bash
FORCE_REINSTALL=1 ./scripts/bootstrap_humble_focal_env.sh
```

## 4. 安装成功后验证

新开终端，或者在当前终端执行：

```bash
source /etc/ros/source_ros2_humble_clean.bash

ros2 pkg prefix rclcpp
ros2 pkg prefix rmw_cyclonedds_cpp
echo "$ROS_DOMAIN_ID"
echo "$RMW_IMPLEMENTATION"
echo "$CYCLONEDDS_URI"
```

期望：

```text
ROS_DOMAIN_ID=20
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
CYCLONEDDS_URI=file:///etc/ros/cyclonedds/pico-cyclonedds.xml
```

目标机还要直接开发 overlay 时，可用严格模式同时检查编译工具和 CMake 版本：

```bash
VERIFY_OVERLAY_BUILD_TOOLS=1 \
  ~/ros2_humble_unified/package_out/artifacts/verify_installed_humble_env.sh
```

也可以执行安装产物里的验证脚本：

```bash
~/ros2_humble_unified/package_out/artifacts/verify_installed_humble_env.sh
```

看到下面这行就说明 Pico 的 Humble 前置环境安装成功：

```text
Installed Humble environment smoke check passed.
```

## 5. 构建完成后 artifacts 是什么

脚本会生成：

```text
~/ros2_humble_unified/package_out/artifacts/
```

里面包含：

```text
install_ros2_humble.sh
install_ros2_humble_markers.sh
verify_installed_humble_env.sh
ros2-humble-focal-desktop-source_*.deb
ros-humble-package-markers_*.tar.gz
rosdep-humble-focal-source-build.yaml
runtime-deps.txt
dev-deps.txt
third_party.repos
source-lock.repos
orin_pico_cyclonedds/
```

这份 `artifacts/` 后续可以复制到其他新 Pico 上安装，不需要每台 Pico 都重新
源码编译。

如果要完全降低网络依赖，建议在已经构建成功的稳定 Pico 上继续打离线包：

```bash
ARTIFACT_DIR=~/ros2_humble_unified/package_out/artifacts \
./packaging/build_offline_humble_bundle.sh
```

生成的 `offline/ros2-humble-focal-offline-bundle_*.tar.gz` 可以直接复制到
其他 Pico 离线安装。详细流程见：

```text
docs/offline-pico-deploy.zh-CN.md
```

其他 Pico 只要执行：

```bash
cd ~/ros2_humble_artifacts
sudo ./install_ros2_humble.sh
source /etc/ros/source_ros2_humble_clean.bash
./verify_installed_humble_env.sh
```

如果 Pico 还保留 ROS 1 的全局 profile，不要在同一个 shell 里直接混 source。
启动 ROS 2 节点前统一用：

```bash
source /etc/ros/source_ros2_humble_clean.bash
```

这个脚本会先清掉 ROS 1 Noetic/Foxy 的环境变量和路径，再加载
`/opt/ros/humble` 与 Pico 的 CycloneDDS 配置。

## 6. 和 Orin 联调

Pico 上启动 server：

```bash
source /etc/ros/source_ros2_humble_clean.bash
python3 /opt/zj_humanoid/tools/ros2_link_test.py server --label pico
```

Orin 的 Humble 容器里启动 client：

```bash
source /opt/ros/humble/setup.bash
python3 /etc/ros/cyclonedds/ros2_link_test.py client --label orin
```

测试通过说明 Pico 和 Orin 之间的 topic、service、action 基础通信都正常。

## 7. 常用重跑方式

保留已经拉好的源码，只重跑构建：

```bash
REBUILD_BASE=1 ./scripts/bootstrap_pico_humble_env.sh
```

清理基础 Humble 源码构建目录后重来：

```bash
CLEAN_BASE=1 ./scripts/bootstrap_pico_humble_env.sh
```

用开发清单试新第三方包：

```bash
PROFILE="$PWD/profiles/third_party.repos" \
./scripts/bootstrap_pico_humble_env.sh
```

并行度按机器资源调整，内存紧张就保持 2：

```bash
COLCON_PARALLEL_WORKERS=2 CMAKE_BUILD_PARALLEL_LEVEL=2 \
./scripts/bootstrap_pico_humble_env.sh
```
