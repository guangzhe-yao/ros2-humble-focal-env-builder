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

已在 `nav01@172.16.11.164` 实机完成：

- ROS 2 Humble Desktop 基础环境安装。
- 16 个第三方源码仓库汇总构建。
- 58 个第三方 ROS 包编译成功。
- 最终环境包含 387 个 ROS 包。
- 生成 387 个对应的 `ros-humble-*` marker deb。
- 自定义功能包依赖并使用 `controller_interface` 编译成功。
- 自定义 Controller 插件通过 pluginlib 动态加载。
- `auto_declare()`、接口配置和 `update()` 调用正常。

## 仓库结构

- `profiles/third_party.repos`：新增和评估第三方包时使用的开发清单。
- `profiles/third_party.lock.repos`：已经验证的精确 commit 清单，用于正式复现。
- `scripts/build_unified_humble_env.sh`：完整汇总构建和出包脚本。
- `scripts/verify_installed_humble_env.sh`：部署后的环境检查脚本。
- `packaging/build_ros2_humble_bundle.sh`：主 deb、marker 和安装器生成脚本。
- `tests/controller_interface_smoke`：自定义 Controller 插件编译和加载测试。
- `docs/adding-third-party-packages.md`：新增第三方包的完整操作流程。
- `docs/risks-and-mitigations.md`：风险和规避方案。
- `docs/focal-build-host-network.md`：实机构建网络配置。

构建目录、日志、install space 和 deb 产物不会提交到 Git。

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
source /opt/ros/humble/setup.bash
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
source /opt/ros/humble/setup.bash
```

如果还有自己的 overlay：

```bash
source /opt/ros/humble/setup.bash
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

## 后续添加第三方官方包

### 第一步：确认依赖是否已经存在

在实机执行：

```bash
source /opt/ros/humble/setup.bash
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
PROFILE="$PWD/profiles/third_party.repos" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PKG_VERSION="0.3.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

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
source /opt/ros/humble/setup.bash
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

