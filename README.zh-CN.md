# Pico ROS 2 Humble 离线开发环境

[English](README.md)

仅面向 Ubuntu 20.04 Focal amd64。提供 ROS 2 上游通用功能包及其运行、编译依赖，
不打包本地项目的节点、消息、模型、控制器、SDK、供应方 runtime 或 Xenomai。
这里的“上游”以 ROS Humble rosdistro 发布记录和原始仓库为依据，不把带 ros 名称的本地包当成官方包。
Humble 的官方 Ubuntu 二进制发行目标是 Jammy；本项目交付的是在 Focal 构建的兼容产物，不混装 Jammy DEB。

## 安装

只需复制一个 `.run` 安装文件到 Pico，无需手工解压：

```bash
sudo bash ros2-humble-focal-offline-bundle_20261111dev3_amd64.run
source /opt/ros/humble/setup.bash
```

自解压入口校验内置负载，再调用包内 install.sh；自动检查升级边界、使用包内 APT 源模拟并安装，
不要求用户运行额外 check。这是软件环境安装包，不是固件，不刷写系统、内核或驱动。
已有 ROS 1、业务工作区、系统网络配置保持不动。若旧基础 DEB 拥有业务包文件，拒绝升级；
业务包拆分迁移必须另行处理，不能靠清空 ROS 或删除 marker 绕过。
不会主动请求升级已有的系统根依赖；新增软件的版本约束仍交由 APT 求解，禁止连带卸载。

## 配置入口

| 文件 | 作用 |
| --- | --- |
| `profiles/pico-ros-packages.txt` | Pico 开发必需的上游 ROS 包，打包时检查缺项 |
| `profiles/humble-environment-packages.txt` | 本版本完整 ROS 包边界，也是断网验收基准 |
| `profiles/excluded-components.txt` | 检查未登记到 ROS 索引的已知业务/供应方残留 |
| `profiles/apt-runtime.txt` | 显式系统运行依赖；ELF 扫描结果额外合并 |
| `profiles/apt-development.txt` | C/C++、CMake、colcon、Python 等开发依赖 |
| `profiles/ros2_humble.repos` | Humble 基础源码配置 |
| `profiles/third_party.lock.repos` | 上游扩展源码配置，发布使用固定提交 |
| `profiles/ros-upstream.json` | 经核对的 Humble 上游包来源索引，不是构建来源证明 |
| `profiles/ros1-migration.json` | ROS 1 到 ROS 2 的功能/API 对应关系 |
| `profiles/pico-simulation-packages.txt` | 仿真候选，默认产物不包含，也不声称已经验证 |

新增 ROS 包须更新源码配置、包边界和必要的系统依赖，然后重新构建、验收。
只修改白名单不会安装软件。删除配置项只改变后续产物要求，不会自动卸载实机已有软件；
已有前缀中的 ROS 包还必须通过重新构建真正移除，不能直接删名单蒙混过关。

## 构建与检查

bootstrap 会准备构建机的 APT/rosdep/Python 工具，只能在专用或隔离构建环境执行，
不要在正在运行机器人的设备宿主系统执行。部署端只运行版本化 .run，内部安装逻辑仍由 install.sh 维护。

```bash
# 在 Focal amd64 构建环境使用全新的工作目录；默认不安装到构建机。
bash builder/bootstrap_pico_humble_env.sh

# 已有干净 underlay：重新打包为新候选，不覆盖旧版本或 latest。
SOURCE_PREFIX=/path/to/clean/install \
WORK_DIR=/path/to/new/release-work \
BUNDLE_VERSION=20261111dev4 \
bash builder/package_installed_pico.sh

# 维护者回归，不安装软件。
bash tests/run_unit_tests.sh

# 只读提取指定 Pico 项目；不扫描 Orin、不编译业务源码。
python3 builder/audit_project_dependencies.py /path/to/pico/project
```

项目扫描涵盖 package.xml、字面量 CMake/launch 引用，并优先标记本地包；动态引用仍需人工核对。
产物中的 `manifest.json` 列出每个实际 DEB 的名称、版本、架构、依赖声明、大小和 SHA256；
`root-packages.txt` 是安装根依赖，`ros-packages.txt` 是 ROS 清单，
`configuration/` 保存配置快照，`artifacts/` 保存来源记录。
tar.gz 只保留为构建中间件；新版本对外只有 .run 一个安装入口，旁侧 SHA256/JSON 是审核元数据。
配置、下载候选、实际安装根和来源证明是不同数据。

目录职责：`builder/` 构建；`profiles/` 配置；`deploy/pico/` 包内安装器；
`tests/` 维护者测试；`release/pico/` 版本化候选；`log/` 本地证据，不提交二进制和日志。

详见[构建与发布](docs/build-release-deploy.zh-CN.md)、
[Pico 依赖与迁移分析](docs/pico-dependencies.zh-CN.md)和[质量契约](docs/quality-contract.zh-CN.md)。
不在本仓库配置固定 IP、DDS 对端或机器人服务。测试通过不代表实机控制功能或人工审核通过。
