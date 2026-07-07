# ROS 2 Humble 前置环境端到端流程

本文说明从开发机修改依赖清单，到构建 Humble 前置环境 artifact，再部署到
Pico 和 Orin 的完整流程。

如果只想看“一台新 Pico 怎么从 0 安装 Humble 前置环境”，先看更短的：

```text
docs/local-to-pico-quickstart.zh-CN.md
```

目标拓扑：

- Pico：Ubuntu 20.04 focal `amd64`，裸机安装 `/opt/ros/humble`。
- Orin：宿主机不安装 ROS 2，ROS 2 节点运行在 Docker 容器里。
- Orin 有线 IP：`192.168.217.100`。
- Pico 有线 IP：`192.168.217.66`。
- RMW：`rmw_cyclonedds_cpp`。
- ROS_DOMAIN_ID：`20`。

## 1. 职责边界

### 本仓库负责什么

`ros2-humble-focal-env-builder` 只负责生成 Pico 的 ROS 2 Humble 前置环境：

- `/opt/ros/humble`
- Focal 上的 `ros-humble-*` marker deb
- 本地 rosdep rules
- CycloneDDS 配置
- DDS sysctl 配置
- Orin/Pico link test 工具

### 本仓库不负责什么

业务部署不放在本仓库：

- Pico 业务节点 deb
- Pico systemd 服务
- 机器人型号配置
- Orin Docker Compose 业务编排
- 业务镜像版本切换

这些属于 `one-stop-upgrade`。后续它只应该消费本仓库生成的 artifact，
不应该在安装时重新构建 ROS 2 Humble。

## 2. 本地无 ROS 2 开发机需要做什么

本地开发机不需要安装 ROS 2，也不需要能运行 `ros2`。

本地开发机只做这些事：

1. 修改文档、脚本和依赖清单。
2. 如果新增第三方 ROS 包，编辑：

   ```text
   profiles/third_party.repos
   ```

3. 可选：准备源码缓存。这个步骤只需要 `git` 和 `vcs`，不需要 ROS 2。

   ```bash
   sudo apt-get update
   sudo apt-get install -y git python3-vcstool rsync

   rm -rf ~/ros2_humble_source_cache
   mkdir -p ~/ros2_humble_source_cache
   vcs import ~/ros2_humble_source_cache < profiles/third_party.repos
   ```

4. 把源码缓存同步到 Focal 构建机：

   ```bash
   rsync -a --delete ~/ros2_humble_source_cache/ \
     <build-user>@<build-host>:~/ros2_humble_source_cache/
   ```

5. 提交清单和文档变更。

本地开发机不能完成最终 artifact 构建，因为构建需要 Ubuntu 20.04 `amd64`
和已有的 Humble base install space。

## 3. Focal 构建机需要准备什么

构建机必须是：

- Ubuntu 20.04 focal
- `amd64`
- 已经存在基础 ROS 2 Humble install space

默认基础路径：

```text
~/ros2_humble/install_deploy/setup.bash
```

如果这台机器没有该基础路径，不能直接运行统一环境构建脚本。需要先恢复或构建
基础 Humble install space，或者明确把 `BASE_PREFIX` 指向一个已经存在的
Humble install prefix。

安装构建工具：

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git curl rsync patchelf \
  python3-pip python3-vcstool python3-rosdep \
  python3-colcon-common-extensions
```

## 4. 构建 Humble 前置环境 artifact

在 Focal 构建机执行：

```bash
cd ~/ros2-humble-focal-env-builder
git pull
export PATH="$HOME/.local/bin:$PATH"

SOURCE_CACHE_DIR="$HOME/ros2_humble_source_cache" \
PROFILE="$PWD/profiles/third_party.repos" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PKG_VERSION="0.3.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

如果构建机可以直接访问 GitHub，也可以不传 `SOURCE_CACHE_DIR`：

```bash
PROFILE="$PWD/profiles/third_party.repos" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PKG_VERSION="0.3.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

构建产物目录：

```text
~/ros2_humble_unified/package_out/artifacts
```

产物中应包含：

```text
install_ros2_humble.sh
install_ros2_humble_markers.sh
verify_installed_humble_env.sh
ros2-humble-focal-desktop-source_<version>_amd64.deb
ros-humble-package-markers_<version>_amd64.tar.gz
rosdep-humble-focal-source-build.yaml
runtime-deps.txt
dev-deps.txt
third_party.repos
source-lock.repos
orin_pico_cyclonedds/
README_DEPLOY.md
```

## 5. 构建机本地验证

先验证尚未安装到 `/opt/ros/humble` 的统一 install space：

```bash
INSTALL_PREFIX="$HOME/ros2_humble_unified/install_deploy" \
  ./scripts/verify_installed_humble_env.sh
```

如果新增了第三方包，还要做下游编译测试：

```bash
rm -rf ~/humble_downstream_compile_test
mkdir -p ~/humble_downstream_compile_test/src
source ~/ros2_humble_unified/install_deploy/setup.bash
cd ~/humble_downstream_compile_test/src

ros2 pkg create \
  --build-type ament_cmake \
  --license Apache-2.0 \
  --dependencies rclcpp <new_dependency> \
  --node-name compile_probe \
  downstream_compile_probe

cd ..
rosdep check --from-paths src --ignore-src \
  --rosdistro humble --os=ubuntu:focal
colcon build --symlink-install
```

## 6. 冻结第三方依赖版本

构建和验证通过后，把实际源码 commit 固定下来：

```bash
cp ~/ros2_humble_unified/package_out/source-lock.repos \
  profiles/third_party.lock.repos

git add profiles/third_party.repos profiles/third_party.lock.repos
git commit -m "Update Humble third-party environment"
```

正式发布和复现应使用：

```bash
PROFILE="$PWD/profiles/third_party.lock.repos" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PKG_VERSION="0.3.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

## 7. 部署到 Pico 实机

Pico 不需要整个仓库，只需要构建产物 `artifacts/`。

从构建机同步到 Pico：

```bash
rsync -a --delete ~/ros2_humble_unified/package_out/artifacts/ \
  nav01@192.168.217.66:~/ros2_humble_artifacts/
```

在 Pico 上安装：

```bash
cd ~/ros2_humble_artifacts
sudo ./install_ros2_humble.sh
source /etc/ros/source_ros2_humble_clean.bash
./verify_installed_humble_env.sh
```

安装完成后，Pico 上会有：

```text
/opt/ros/humble
/etc/ros/cyclonedds/pico-cyclonedds.xml
/etc/ros/ros2_humble_cyclone.env
/etc/ros/source_ros2_humble_clean.bash
/etc/profile.d/ros2_humble_cyclone.sh
/etc/sysctl.d/10-ros2-dds.conf
/opt/zj_humanoid/tools/ros2_link_test.py
/opt/zj_humanoid/tools/source_ros2_humble_clean.bash
```

如果是覆盖旧环境：

```bash
sudo systemctl stop zj_humanoid.service || true
sudo apt remove -y 'ros-humble-*' ros2-humble-focal-desktop-source
sudo rm -rf /opt/ros/humble

cd ~/ros2_humble_artifacts
sudo ./install_ros2_humble.sh
```

不要把两个版本的 `/opt/ros/humble` 文件混在一起。

## 8. 配置 Orin 实机

Orin 宿主机不需要安装 ROS 2。它需要：

- Docker 镜像中有 `/opt/ros/humble`
- Docker 使用 host 网络
- Docker 使用 host IPC
- 所有 ROS 2 容器使用同一组 DDS 环境变量
- 挂载 Orin 侧 CycloneDDS XML

调试容器可以直接使用本仓库提供的脚本：

```bash
cd deploy/orin_pico_cyclonedds
./start_orin_humble_container.sh
```

在正式 `one-stop-upgrade` 的 compose 中，建议使用统一 anchor：

```yaml
x-ros2-env: &ros2-env
  ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-20}
  ROS_LOCALHOST_ONLY: "0"
  RMW_IMPLEMENTATION: rmw_cyclonedds_cpp
  CYCLONEDDS_URI: file:///etc/ros/cyclonedds/orin-cyclonedds.xml

x-ros2-volumes: &ros2-volumes
  - ./config/ros2/orin-cyclonedds.xml:/etc/ros/cyclonedds/orin-cyclonedds.xml:ro

services:
  sensor:
    image: 10.51.33.201:30002/navi_project/sensor:22CUDA_humble
    network_mode: host
    ipc: host
    environment:
      <<: *ros2-env
    volumes: *ros2-volumes
```

ROS 2 没有 `roscore`，所以不需要 `roscore_service`。但可以保留“统一配置”
这个设计，只是统一配置应该来自 `.env`、compose anchor 和挂载的 XML，
不是来自一个中心 ROS 进程。

## 9. Orin/Pico 通信验证

Pico 启动测试 server：

```bash
source /etc/ros/source_ros2_humble_clean.bash
python3 /opt/zj_humanoid/tools/ros2_link_test.py server --label pico
```

Orin 容器中启动 client：

```bash
docker exec -it orin_humble_cyclone bash -lc '
  source /opt/ros/humble/setup.bash
  python3 /etc/ros/cyclonedds/ros2_link_test.py client --label orin
'
```

反向验证时，把 server 放到 Orin 容器，client 放到 Pico。

这个测试覆盖：

- Pico 到 Orin 的 topic
- Orin 到 Pico 的 topic
- service
- action feedback/result

## 10. 接入 one-stop-upgrade 的原则

等本仓库的 artifact 在新 Pico 上验证稳定后，再改 `one-stop-upgrade`。

建议接入方式：

1. `one-stop-upgrade` 的 `versions/version.json` 增加 Humble 环境 artifact URL。
2. `PicoManager.install()` 先安装或校验 Humble 前置环境。
3. 再安装业务 ROS 2 deb。
4. 最后安装 systemd 和启动业务 bringup。

`one-stop-upgrade` 不应该从源码构建 Humble，也不应该直接散装第三方 ROS 2
依赖。新增第三方依赖必须先进入本仓库，重新发布前置环境 artifact。

## 11. 常见问题

### 本地没有 ROS 2 能不能改依赖清单？

可以。编辑 `profiles/third_party.repos` 不需要 ROS 2。最终是否能构建和运行，
由 Focal 构建机和 Pico 实机验证。

### Pico 上要不要拷整个仓库？

不要。Pico 只需要 `artifacts/` 目录。

### Orin 上要不要安装 `/opt/ros/humble`？

不要。Orin 的 ROS 2 环境在 Docker 镜像里。

### 业务节点已经启动后再 export RMW 可以吗？

不可以。RMW 是进程启动时决定的，必须带着正确环境变量重启节点。

### 新增第三方 ROS 2 包后可以只在 Pico apt install 吗？

不建议。Focal 没有官方 Humble apt 仓库，散装会破坏可复现性。应该加入
`profiles/third_party.repos`，重新构建并发布新的前置环境 artifact。
