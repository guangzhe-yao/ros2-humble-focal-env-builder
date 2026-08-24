# Pico 离线交付目录

把本目录整体发给下一台 Pico，然后执行：

```bash
chmod +x install.sh
./install.sh
```

`install.sh` 会校验 SHA256、解压离线包、安装 `/opt/ros/humble`，并运行环境
冒烟测试。安装过程不访问网络。

交付目录必须包含：

```text
install.sh
ros2-humble-focal-offline-bundle_<version>_amd64.tar.gz
ros2-humble-focal-offline-bundle_<version>_amd64.tar.gz.sha256
```

目标机器要求 Ubuntu 20.04 focal amd64。离线包可以放在任意目录，但安装前缀
固定为 `/opt/ros/humble`。

当前本地已验证交付包：

```text
ros2-humble-focal-offline-bundle_202608241111_amd64.tar.gz
SHA256: 00c7397cc7614661485598aff374a91485b65f65ea04db6de0a984f45d34fb80
ROS package/marker: 401/401
offline apt deb: 450
```

该包已在 `ubuntu:20.04` 断网容器中从空系统完成一键安装和 CycloneDDS 节点
创建验证。
