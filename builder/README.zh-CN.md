# 构建与出包

本目录只放构建工具，不放最终交付物。所有命令必须在 Ubuntu 20.04 focal
amd64 Pico 或同规格构建机上运行。

## 从零构建

```bash
./builder/bootstrap_pico_humble_env.sh
```

## 从干净 underlay 生成候选包

```bash
SOURCE_PREFIX=/path/to/clean/humble/install \
BUNDLE_VERSION=20261016dev1 \
bash builder/package_installed_pico.sh
```

该命令重新生成主 deb、marker deb 和离线 apt 依赖，把版本化 tar 包与
SHA256 放到 `release/pico/`，不覆盖同名文件，也不自动更新 latest。
默认源仍是 `/opt/ros/humble`，但已部署业务 overlay 的前缀不能作为发布源。
`OFFLINE_OUT_DIR` 可指定中间离线产物目录。缺少真实源码锁定记录时会告警，
不会把配置文件冒充为 `source-lock.repos`。

低层出包实现位于 `builder/package/`。日常发布不要绕过上面的统一入口。

维护者回归入口为 `bash tests/run_unit_tests.sh`；候选包的断网验收和人工
发布步骤见 [构建与发布](../docs/build-release-deploy.zh-CN.md)。
