# 构建与出包

本目录只放构建工具，不放最终交付物。所有命令必须在 Ubuntu 20.04 focal
amd64 Pico 或同规格构建机上运行。

## 从零构建

```bash
./builder/bootstrap_pico_humble_env.sh
```

## 从已安装且验证通过的 Pico 生成离线交付包

```bash
./builder/package_installed_pico.sh
```

该命令读取 `/opt/ros/humble`，重新生成主 deb、marker deb 和全部离线 apt
依赖，然后把最终 tar 包与 SHA256 放到 `release/pico/`。

低层出包实现位于 `builder/package/`。日常发布不要绕过上面的统一入口。
