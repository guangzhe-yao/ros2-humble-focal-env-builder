# ROS 2 Humble Focal 环境构建器

[English](README.md) | [简体中文](README.zh-CN.md)

本仓库用于在 Ubuntu 20.04 Focal amd64 上重复构建 ROS 2 Humble Desktop，
并将经过验证的官方或自定义第三方 ROS 2 功能包合入同一个
`/opt/ros/humble` 部署环境。

适用场景：

- 目标机器均为 Ubuntu 20.04 amd64。
- 需要使用 ROS 2 Humble，但 Focal 没有完整的官方 Humble 二进制仓库。
- 多个业务模块会逐步统计和增加第三方 ROS 2 依赖。
- 希望最终通过一个安装脚本部署完整环境。

## 当前验证状态

已在 `nav01@172.16.11.164` 和 `nav01@172.16.10.11` 实机完成：

- ROS 2 Humble Desktop 基础环境安装。
- 18 个第三方源码仓库锁定和离线缓存构建。
- 70 个第三方 ROS 包编译成功。
- 最终环境包含 399 个 ROS 包。
- 生成 399 个对应的 `ros-humble-*` marker deb。
- 自定义功能包依赖并使用 `controller_interface` 编译成功。
- 自定义 Controller 插件通过 pluginlib 动态加载。
- `auto_declare()`、接口配置和 `update()` 调用正常。
- Foxy lowerlimb 项目迁移后 9 个包完成干净构建，单测和插件发现通过。

## 仓库结构

- `profiles/third_party.repos`：新增和评估第三方包时使用的开发清单。
- `profiles/third_party.lock.repos`：已经验证的精确 commit 清单，用于正式复现。
- `profiles/ros2_humble.repos`：ROS 2 Humble 官方基础源码清单。
- `scripts/bootstrap_humble_focal_env.sh`：在一台新 Pico/Focal amd64
  实机上从 0 拉取 Humble 源码、构建、打包并安装前置环境。
- `scripts/bootstrap_pico_humble_env.sh`：Pico 实机推荐入口，内置当前验证过的
  GitHub 代理和 2 并行构建默认值，最终调用上面的通用 bootstrap。
- `scripts/build_unified_humble_env.sh`：完整汇总构建和出包脚本。
- `scripts/verify_installed_humble_env.sh`：部署后的环境检查脚本。
- `packaging/build_ros2_humble_bundle.sh`：主 deb、marker 和安装器生成脚本。
- `packaging/build_offline_humble_bundle.sh`：把已验证 artifacts 和 apt 依赖
  打成可复制到其他 Pico 的离线安装包。
- `packaging/repackage_existing_humble_artifacts.sh`：稳定 Pico 已经有
  `~/ros2_humble_unified/install_deploy` 时，不重新源码构建，只重新生成当前
  仓库版本的 artifacts/离线包。
- `tests/controller_interface_smoke`：自定义 Controller 插件编译和加载测试。
- `docs/adding-third-party-packages.md`：新增第三方包的完整操作流程。
- `docs/risks-and-mitigations.md`：风险和规避方案。
- `docs/focal-build-host-network.md`：实机构建网络配置。
- `docs/new-pico-repeatable-deploy.md`：新 Pico 机器可重复安装 Humble
  前置环境的闭环。
- `docs/offline-pico-deploy.zh-CN.md`：稳定 Pico 打离线包、其他 Pico 离线安装流程。
- `docs/local-to-pico-quickstart.zh-CN.md`：一台新 Pico 从 0 安装
  Humble 前置环境的最短操作路径。
- `docs/end-to-end-workflow.zh-CN.md`：从本地开发机、Focal 构建机到
  Pico/Orin 实机部署的端到端流程。
- `deploy/orin_pico_cyclonedds`：Orin Docker 与 Pico 固定有线 IP 的
  CycloneDDS 配置、容器启动脚本和 topic/service/action 冒烟测试。

构建目录、日志、install space 和 deb 产物不会提交到 Git。

## Orin/Pico 多机通信部署

当前机器人拓扑已按以下固定 IP 验证：

- Orin 有线口：`192.168.217.100`
- Pico 有线口：`192.168.217.66`
- Orin Humble 镜像：
  `10.51.33.201:30002/navi_project/sensor:22CUDA_humble`
- RMW：`rmw_cyclonedds_cpp`
- DDS 发现方式：禁用 multicast，固定 unicast peers。

部署和测试入口：

```bash
cd deploy/orin_pico_cyclonedds
```

详见：

```text
deploy/orin_pico_cyclonedds/README.zh-CN.md
```

该目录里的 `ros2_link_test.py` 已用于双向验证：

- Pico server / Orin client：topic、service、action 正常。
- Orin server / Pico client：topic、service、action 正常。

业务节点必须在启动前设置同一组环境变量：

```bash
export ROS_DOMAIN_ID=20
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file:///etc/ros/cyclonedds/<对应机器配置>.xml
```

注意：RMW 是进程启动时决定的，已经运行中的 ROS 2 节点不能通过后续修改
环境变量切换到 CycloneDDS，需要用上述环境重启。

生成的 artifact 会携带 `deploy/orin_pico_cyclonedds`，`install_ros2_humble.sh`
在新 Pico 上安装时会自动部署 Pico 侧 CycloneDDS、DDS sysctl 和
`ros2_link_test.py`。详见：

```text
docs/new-pico-repeatable-deploy.md
docs/end-to-end-workflow.zh-CN.md
```

## 自定义功能包能否正常使用第三方官方包

可以。安装统一环境后，自定义功能包按照正常 ROS 2 Humble 开发方式编码即可。

例如使用 `controller_interface`：

```xml
<!-- package.xml -->
<depend>controller_interface</depend>
<depend>pluginlib</depend>
<depend>rclcpp</depend>
```

```cmake
# CMakeLists.txt
find_package(controller_interface REQUIRED)
find_package(pluginlib REQUIRED)
find_package(rclcpp REQUIRED)

ament_target_dependencies(my_controller
  controller_interface
  pluginlib
  rclcpp
)
```

编译前加载统一环境：

```bash
source /etc/ros/source_ros2_humble_clean.bash
colcon build --symlink-install
source install/setup.bash
```

已验证示例：

```bash
cd tests/controller_interface_smoke
```

该示例继承 `controller_interface::ControllerInterface`，通过 pluginlib 导出，
并由独立程序动态加载和执行。

## 开发时需要注意

### 1. 必须先加载基础环境

每个新终端都要执行：

```bash
source /etc/ros/source_ros2_humble_clean.bash
```

如果还有自己的 overlay：

```bash
source /etc/ros/source_ros2_humble_clean.bash
source ~/my_ws/install/setup.bash
```

顺序不能反。

### 2. 正确声明依赖

代码里使用的 ROS 包必须同时写入：

- `package.xml`
- `CMakeLists.txt` 或 Python 包配置

不要仅靠当前机器“碰巧能找到头文件”。

### 3. Focal 没有完整的官方 Humble deb

如果新功能包依赖的 ROS 包不在当前统一环境中，`rosdep` 可能无法在 Focal
上通过 apt 安装它。此时需要把该 ROS 包及其缺失的 ROS 依赖加入
`profiles/third_party.repos`，重新构建统一环境。

普通 Ubuntu 系统依赖仍由 rosdep/apt 安装，例如：

```bash
rosdep install --from-paths src --ignore-src -y \
  --rosdistro humble --os=ubuntu:focal
```

### 4. 不要混用其他 ROS 环境

避免同时 source：

- ROS 1 Noetic
- Jammy 上安装的 Humble
- 其他 `/opt/ros/<distro>`
- 旧的 Humble overlay

检查当前环境：

```bash
echo "$AMENT_PREFIX_PATH"
echo "$CMAKE_PREFIX_PATH"
ros2 pkg prefix rclcpp
```

统一环境中的包应该指向 `/opt/ros/humble`。

### 5. 注意 Python 和工具链版本

- Focal 默认 Python 是 3.8。
- 部分面向 Jammy 的新包可能使用 Python 3.10 特性。
- 当前 `ros2_control` 依赖链需要 CMake 3.22+。
- 构建时应确保 `$HOME/.local/bin` 位于 PATH 前面。

```bash
export PATH="$HOME/.local/bin:$PATH"
cmake --version
```

### 6. 不能只验证“编译成功”

新增包至少应检查：

- `rosdep check`
- `colcon build`
- `ros2 pkg prefix <package>`
- pluginlib 插件能否加载
- launch 文件能否启动
- 参数文件能否读取
- 与硬件、DDS、设备权限相关的运行测试

## 新 Pico 从 0 安装

如果 Pico 上没有任何 Humble 环境，直接在 Pico 上运行：

```bash
cd /home/nav01/Public/ros2-humble-focal-env-builder

./scripts/bootstrap_pico_humble_env.sh
```

该脚本会根据 `profiles/ros2_humble.repos` 拉取 ROS 2 Humble 官方源码、按
`profiles/third_party.lock.repos` 合入第三方包、生成 `artifacts/`，并安装到
`/opt/ros/humble`。

新增第三方包时修改：

```text
profiles/third_party.repos
```

详见：

```text
docs/local-to-pico-quickstart.zh-CN.md
```

## 后续添加第三方官方包

### 第一步：确认依赖是否已经存在

在实机执行：

```bash
source /etc/ros/source_ros2_humble_clean.bash
ros2 pkg prefix <package_name>
rosdep resolve <package_name> --rosdistro humble --os=ubuntu:focal
```

如果 `ros2 pkg prefix` 成功，通常不需要重复加入源码清单。

### 第二步：修改开发清单

编辑：

```text
profiles/third_party.repos
```

加入：

- 顶层第三方仓库。
- Focal 上无法通过 apt 获取的 ROS 源码依赖。
- 与 Humble 兼容的 branch、tag 或 commit。

评估阶段可以使用分支；正式发布前必须生成并保存精确 commit 清单。

### 第三步：准备源码

实机网络可直接访问 GitHub 时：

```bash
rm -rf ~/ros2_humble_source_cache
mkdir -p ~/ros2_humble_source_cache
vcs import ~/ros2_humble_source_cache < profiles/third_party.repos
```

无法直接访问 GitHub 时，可在其他机器准备源码后同步：

```bash
rsync -a --delete ~/ros2_humble_source_cache/ \
  nav01@172.16.11.164:~/ros2_humble_source_cache/
```

缓存中不要保留清单之外的仓库。

### 第四步：重新汇总构建和出包

在 Focal 实机执行：

```bash
cd ~/Desktop/jenkins/ros2-humble-focal-env-builder
git pull
export PATH="$HOME/.local/bin:$PATH"

SOURCE_CACHE_DIR="$HOME/ros2_humble_source_cache" \
COLCON_CMAKE_ARGS="-DCMAKE_DISABLE_FIND_PACKAGE_Doxygen=TRUE" \
PROFILE="$PWD/profiles/third_party.repos" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PKG_VERSION="0.3.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

禁用 Doxygen 可避免 RSL 在生成文档时隐式访问 GitHub 下载 CSS；源码缓存
构建因此不依赖 GitHub 在线状态。

产物目录：

```text
~/ros2_humble_unified/package_out/artifacts
```

主要产物：

- `ros2-humble-focal-desktop-source_<version>_amd64.deb`
- `ros-humble-package-markers_<version>_amd64.tar.gz`
- `rosdep-humble-focal-source-build.yaml`
- `install_ros2_humble.sh`
- `source-lock.repos`
- `verify_installed_humble_env.sh`

### 第五步：验证新环境

先检查尚未部署的统一 install space：

```bash
INSTALL_PREFIX="$HOME/ros2_humble_unified/install_deploy" \
  ./scripts/verify_installed_humble_env.sh
```

再创建一个小型下游功能包，真实依赖新增第三方包并完成编译和运行测试。

### 第六步：冻结正式版本

验证通过后：

```bash
cp ~/ros2_humble_unified/package_out/source-lock.repos \
  profiles/third_party.lock.repos

git add profiles/third_party.repos profiles/third_party.lock.repos
git commit -m "Add <module> dependencies to unified Humble environment"
git push origin main
```

之后正式复现应使用：

```bash
PROFILE="$PWD/profiles/third_party.lock.repos" \
PKG_VERSION="0.3.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

### 第七步：覆盖安装

在目标机器上不要混装两个版本：

```bash
sudo apt remove -y 'ros-humble-*' ros2-humble-focal-desktop-source
sudo rm -rf /opt/ros/humble

cd artifacts
sudo ./install_ros2_humble.sh
source /etc/ros/source_ros2_humble_clean.bash
./verify_installed_humble_env.sh
```

## 快速构建当前已验证版本

```bash
cd ~/Desktop/jenkins/ros2-humble-focal-env-builder
export PATH="$HOME/.local/bin:$PATH"

PROFILE="$PWD/profiles/third_party.lock.repos" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PKG_VERSION="0.2.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

## 风险说明

该环境适合受控的内部 Ubuntu 20.04 amd64 机器，但不是官方 Ubuntu 22.04
Humble apt 环境。正式发布前请阅读：

[风险和规避方案](docs/risks-and-mitigations.md)
