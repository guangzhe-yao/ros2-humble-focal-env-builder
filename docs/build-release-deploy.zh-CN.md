# Pico Humble 构建、发布与离线部署

## 1. 职责边界

本仓库只负责 Pico：

- 构建 Ubuntu 20.04 amd64 上的 ROS 2 Humble。
- 生成可安装到 `/opt/ros/humble` 的主 deb 和 marker deb。
- 收集完整运行时 apt 依赖，生成本地 apt 仓库。
- 安装 Pico CycloneDDS 配置并验证 ROS 2 环境。

Orin 的 Ubuntu 22.04、Docker、业务镜像和 Compose 不由本仓库处理。

## 2. 验证现有 Pico

```bash
./deploy/pico/verify_installed_humble_env.sh
```

只有验证通过的 `/opt/ros/humble` 才能作为发布源。

## 3. 从已安装环境发布

```bash
./builder/package_installed_pico.sh
```

默认行为：

- 输入：`/opt/ros/humble`
- 构建工作目录：`~/ros2_humble_release_build`
- 源码版本清单：`profiles/third_party.lock.repos`
- 输出：`release/pico/`
- 若任何 apt 依赖无法下载，停止出包，不生成不完整的正式包。

需要自定义时可以覆盖环境变量：

```bash
SOURCE_PREFIX=/opt/ros/humble \
WORK_DIR="$HOME/ros2_humble_release_build" \
PKG_VERSION="0.3.1+$(date +%Y%m%d%H%M)" \
BUNDLE_VERSION="$(date +%Y%m%d%H%M)" \
./builder/package_installed_pico.sh
```

## 4. 产物是否依赖构建路径

不依赖构建机的用户名和工作目录。出包过程会：

- 展开 install space 内的符号链接。
- 将文本中的构建前缀改写为 `/opt/ros/humble`。
- 改写 ELF RPATH/RUNPATH。
- 重新生成单前缀 `setup.*` 文件。
- 排除 `__pycache__` 和 `.pyc`。

因此 tar 包可放在目标 Pico 的任意目录运行。它不是任意系统通用包，目标机器仍
必须是 Ubuntu 20.04 focal amd64，安装位置固定为 `/opt/ros/humble`。

## 5. 一键离线部署

将整个 `release/pico/` 目录复制到目标 Pico：

```bash
rsync -aL release/pico/ nav01@<target-ip>:~/pico_humble_release/
```

目标机执行：

```bash
cd ~/pico_humble_release
./install.sh
```

安装器不执行 `apt update`，只使用 tar 包内的 `apt_debs/` 本地仓库。安装前若
目标系统自身已经存在断裂的 dpkg/apt 状态，安装器会停止并要求先修复基础系统。

## 6. 从零构建

当没有可复用的 `/opt/ros/humble` 时，在联网的 Ubuntu 20.04 amd64 构建机执行：

```bash
./builder/bootstrap_pico_humble_env.sh
```

正式复现应使用 `profiles/third_party.lock.repos`。新增或升级第三方源码后，先按
`docs/adding-third-party-packages.md` 完成构建和下游验证，再更新 lock 文件。

## 7. 发布检查

正式交付前至少确认：

```bash
sha256sum -c release/pico/ros2-humble-focal-offline-bundle_*_amd64.tar.gz.sha256
./tests/test_offline_bundle_dependency_collection.sh
bash -n builder/*.sh builder/package/*.sh deploy/pico/*.bash release/pico/install.sh
```

最终还应在一台非出包机、断网状态下运行 `release/pico/install.sh`。这是完整离线
能力的最终验收；仅在原构建机上解包不能替代该测试。
