# Humble 开发环境构建、发布与离线安装

## 边界

构建器只管理 Ubuntu 20.04 amd64 的 Humble underlay 和通用开发依赖。
自定义 robot-state、lowerlimb、上肢接口由各自仓库发布。
vendor runtime、SDK、Xenomai 用户态和内核由系统负责，均不纳入此发布包。

## 发布源

从干净的 Humble install space 打包，不从已部署整机业务的前缀直接打包：

```bash
SOURCE_PREFIX=/path/to/clean/humble/install \
PKG_VERSION=0.3.3+20261015 \
BUNDLE_VERSION=20261015dev1 \
bash builder/package_installed_pico.sh
```

也可以使用 `builder/bootstrap_pico_humble_env.sh` 从源码构建，
源码锁定清单在 `profiles/`。新增通用 ROS 包后需更新
`profiles/humble-environment-packages.txt`，并验证下游编译。

打包只处理暂存副本，不修改源安装树。旧基础环境误带的两个业务包从暂存树排除；
其他未知 overlay 包直接报错，避免只删包名却留下业务共享库。
ELF RPATH、安装前缀和 ament 索引沿用已有重定位逻辑。

默认包含 `dev-deps.txt` 中的开发工具。离线 apt 缓存可通过
`CACHED_APT_DEBS_DIR` 复用；只复制依赖闭包需要的系统包，不复制缓存中的
业务、vendor 或其他 ROS 发行版 DEB。打包后再次拒绝业务/vendor 包。
编译机需要 `dpkg-dev`、`patchelf`、`rsync` 和正常的 Focal apt 源。

## 安装

```bash
tar -xzf ros2-humble-focal-offline-bundle_20261015dev1_amd64.tar.gz
cd ros2-humble-focal-offline-bundle_20261015dev1_amd64
sudo bash install.sh
source /opt/ros/humble/setup.bash
```

只有一个直接安装入口，不提供 check 模式。完整性校验自动执行；
apt 使用包内私有 file 源，不使用在线软件源。
不清空 `/opt/ros/humble`，不修改系统已有 runtime/SDK/Xenomai，
不卸载业务 DEB、不安装机器人服务。安装通用系统依赖时，其标准 dpkg
钩子仍可能调用 ldconfig；既有 vendor 库的符号链接告警不由构建器修复。

`apt list --installed` 显示安装版本，`apt-cache depends` 显示依赖。
ROS marker 的版本绑定基础环境版本，实际 ROS 内容由主 DEB 提供。
源码升级到其他 ROS/Ubuntu 版本需要对应平台重编译，不能混用二进制。

## 发布验证

维护者在全新 Ubuntu 20.04 容器内禁用网络，执行完整安装，再运行
`tests/test_development_release.sh`。该测试检查没有 vendor 目录、
核对 ROS 包清单，使用 colcon 构建 C++ 节点和自定义消息，并导入 Python
类型支持、执行测试节点。测试夹具不会进入基础环境或发布包。

这些是发布前内部测试，不要求部署用户额外执行验证命令。
rosdep 网络索引和任意业务项目的专用依赖不包含在开发环境的离线保证内。
