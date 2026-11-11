# Humble 开发环境构建、发布与离线安装

## 边界

构建器只管理 Ubuntu 20.04 amd64 的 Humble underlay 和通用开发依赖。
自定义 robot-state、lowerlimb、上肢接口由各自仓库发布。
vendor runtime、SDK、Xenomai 用户态和内核由系统负责，均不纳入此发布包。

## 发布源

从干净的 Humble install space 打包，不从已部署整机业务的前缀直接打包：

```bash
SOURCE_PREFIX=/path/to/clean/humble/install \
PKG_VERSION=0.3.4+20261111 \
BUNDLE_VERSION=20261111dev4 \
bash builder/package_installed_pico.sh
```

也可以使用 `builder/bootstrap_pico_humble_env.sh` 从源码构建，
源码锁定清单在 `profiles/`。新增通用 ROS 包后需更新
`profiles/humble-environment-packages.txt`，并验证下游编译。

打包只处理干净上游环境，不修改源安装树。任何名单外 overlay 包直接拒绝，
不再猜测并删除业务文件。缺少 pico-ros-packages.txt 中的必需包也拒绝出包。
ELF RPATH、安装前缀和 ament 索引沿用已有重定位逻辑。

运行和开发根依赖分别维护在 profiles/apt-runtime.txt、profiles/apt-development.txt，
打包生成 runtime-deps.txt 和 dev-deps.txt。离线 apt 缓存可通过
`CACHED_APT_DEBS_DIR` 复用；只复制依赖闭包需要的系统包，不复制缓存中的
业务、vendor 或其他 ROS 发行版 DEB。打包后再次拒绝业务/vendor 包。
编译机需要 `dpkg-dev`、`patchelf`、`rsync` 和正常的 Focal apt 源。

主 DEB 和 marker 归档必须各一个，名称、版本、架构一致。
同名离线输出目录或归档已存在时拒绝覆盖；重试请使用新版本/新输出目录，
不要为重试而删除源安装空间。所有构建/出包目录应使用新路径，脚本不自动清空旧输出。
bootstrap 默认不安装到构建机。`SOURCE_LOCK` 应指向真实构建来源记录；
缺失时不生成 `source-lock.repos`，并明确报告来源未知。

`package_installed_pico.sh` 只发布 .run 候选与校验信息，不自动切换 latest。
tar.gz 是内部备包中间件。自解压包装器拒绝归档目录穿越、绝对路径、链接和多个根目录；
运行时先核对负载 SHA256 再解包，不复制另一套安装逻辑。
`A | B` 两项均参与下载候选收集，但不会变成必须同时安装的根依赖。
离线 apt 求解仍保留 DEB 中的版本约束和 Pre-Depends。

## 安装

```bash
sudo bash ros2-humble-focal-offline-bundle_20261111dev3_amd64.run
source /opt/ros/humble/setup.bash
```

只有一个直接安装入口，不提供 check 模式。完整性校验自动执行；
apt 使用包内私有 file 源，不使用在线软件源。
不清空 `/opt/ros/humble`，不修改系统已有 runtime/SDK/Xenomai，
不卸载业务 DEB、不安装机器人服务。旧基础 DEB 若拥有不在新清单中的 ROS 包，
或仍有旧业务 marker，安装器在 APT 操作前拒绝升级，要求另行完成业务包迁移。
对已有且未指定版本的系统根依赖，不再显式请求升级；APT 仍须满足新增包的版本约束，
`--no-remove` 阻止为升级环境而卸载其他软件。整机系统升级不属于本构建器职责。
安装通用系统依赖时，其标准 dpkg
钩子仍可能调用 ldconfig；既有 vendor 库的符号链接告警不由构建器修复。

`apt list --installed` 显示安装版本，`apt-cache depends` 显示依赖。
ROS marker 的版本绑定基础环境版本，实际 ROS 内容由主 DEB 提供。
源码升级到其他 ROS/Ubuntu 版本需要对应平台重编译，不能混用二进制。

## 发布验证

维护者在全新 Ubuntu 20.04 容器内禁用网络，执行完整安装，再运行
`tests/test_development_release.sh`。该测试检查没有 vendor 目录、
核对 ROS 包清单、导入 joy_teleop 和 teleop_tools_msgs，使用 colcon 构建 C++ 节点、
自定义消息和无硬件 controller_interface 测试插件。测试夹具不会进入基础环境或发布包。

每个包内的 manifest.json 记录所有实际 DEB 的版本、架构、大小与 SHA256；
configuration/ 保存配置快照。artifacts/build-provenance.json 可记录已知来源，
例如旧二进制基础归档和本轮真实编译提交；部分来源必须标记 partial，不冒充完整重编译。
只有下载完整依赖闭包并通过断网安装/开发测试的候选才可声明相应离线能力。

这些是发布前内部测试，不要求部署用户额外执行验证命令。
rosdep 网络索引和任意业务项目的专用依赖不包含在开发环境的离线保证内。

先运行不安装软件、不联网的维护者回归：

```bash
bash tests/run_unit_tests.sh
```

候选包发生变化时，在本机已有 `ubuntu:20.04` 镜像的前提下，使用断网容器
运行安装及开发验收，不能将该命令改成在宿主机执行包内安装脚本：

```bash
candidate=ros2-humble-focal-offline-bundle_20261111dev3_amd64.run
mkdir -p log
docker run --rm --network none \
  -v "$PWD:/validation:ro" -e CANDIDATE="$candidate" \
  ubuntu:20.04 bash -c \
  'bash "/validation/release/pico/$CANDIDATE" &&
   bash /validation/tests/test_development_release.sh' \
  > "log/$candidate.acceptance.log" 2>&1
```

**仅在人工审阅变更、SHA256、验收日志和未验证项后**，维护者更新发布清单，
再明确选中已审核的候选（下面变量需替换为实际已审核版本）：

```bash
cd release/pico
candidate=ros2-humble-focal-offline-bundle_20261111dev3_amd64.run
sha256sum -c "$candidate.sha256" &&
ln -sfn "$candidate" ros2-humble-focal-offline-bundle_latest_amd64.run &&
ln -sfn "$candidate.sha256" ros2-humble-focal-offline-bundle_latest_amd64.run.sha256
```

此处是维护者发布流程，不是部署用户需要执行的额外 check 步骤。
详细边界和审核责任见 [质量契约](quality-contract.zh-CN.md)。
