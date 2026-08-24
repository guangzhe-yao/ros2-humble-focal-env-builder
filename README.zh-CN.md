# ROS 2 Humble Focal Pico 环境构建器

[English](README.md)

本仓库只负责 Ubuntu 20.04 focal amd64 Pico 的 ROS 2 Humble 环境：构建、出包、
离线部署和验证。Orin 使用 Ubuntu 22.04 与现有 Docker，不在本仓库部署范围内。

## 当前基线

已在 Pico `nav01@172.16.10.245` 验证：

- `/opt/ros/humble` 可正常加载。
- ROS 2 package 数量：401。
- `ros-humble-*` marker 数量：401。
- `rclpy`、CycloneDDS、RViz2、ros2_control 和 bash completion 冒烟测试通过。
- 默认 `ROS_DOMAIN_ID=20`，Pico CycloneDDS 配置可创建节点。

## 目录结构

```text
builder/                 构建、重新出包工具
  package/               deb、marker、离线 apt 仓库的底层打包实现
deploy/pico/             安装到 Pico 的 DDS 配置、环境加载与验证工具
profiles/                ROS 2 和第三方源码锁定清单、overlay apt 依赖
release/pico/            可直接交付下一台 Pico 的最终离线包与一键安装入口
tests/                   打包逻辑和 controller_interface 冒烟测试
docs/                    依赖维护、风险和完整操作说明
```

构建中间目录与最终二进制产物不提交 Git。最终 tar 包在本机明确放到
`release/pico/`，源码分支只保存可复现的脚本、配置和校验逻辑。

## 已验证 Pico 重新出包

在 Ubuntu 20.04 amd64 Pico 上执行：

```bash
git pull
./builder/package_installed_pico.sh
```

该命令从已经验证的 `/opt/ros/humble` 生成新的离线包，并写入：

```text
release/pico/ros2-humble-focal-offline-bundle_<version>_amd64.tar.gz
release/pico/ros2-humble-focal-offline-bundle_<version>_amd64.tar.gz.sha256
```

出包机需要网络下载 Ubuntu 依赖；目标部署机不需要网络。

## 新 Pico 一键离线部署

把 `release/pico/` 整个目录复制到目标 Pico：

```bash
cd release/pico
./install.sh
```

安装器会自动完成 SHA256 校验、解压、离线 apt 依赖安装、主 deb/marker 安装、
Pico CycloneDDS 配置和最终冒烟测试。

离线包可以从任意目录运行，不依赖构建机的用户名或工作目录。目标约束仍然是：

- Ubuntu 20.04 focal
- amd64
- 安装前缀 `/opt/ros/humble`

## 从零构建

新构建机需要联网获取源码与系统依赖：

```bash
./builder/bootstrap_pico_humble_env.sh
```

详细流程见 [构建、发布与部署](docs/build-release-deploy.zh-CN.md)。新增第三方包见
[第三方包维护](docs/adding-third-party-packages.md)。
