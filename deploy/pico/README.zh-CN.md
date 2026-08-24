# Pico 运行配置

这里仅包含安装到 Pico 的运行配置和验证工具，不负责 Orin 的 Docker 环境。

默认参数：

- Pico 有线 IP：`192.168.217.66`
- DDS 对端：`192.168.217.100`
- `ROS_DOMAIN_ID=20`
- `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`
- CycloneDDS 使用固定单播发现，禁用 multicast。

离线包的安装器会自动安装本目录内容：

```text
/etc/ros/cyclonedds/pico-cyclonedds.xml
/etc/sysctl.d/10-ros2-dds.conf
/etc/ros/source_ros2_humble_clean.bash
/opt/zj_humanoid/tools/ros2_link_test.py
```

安装后验证：

```bash
source /etc/ros/source_ros2_humble_clean.bash
/opt/zj_humanoid/tools/ros2_link_test.py server --label pico
```

若实际 Pico IP、DDS 对端 IP 或 Domain ID 不同，必须在出包前修改配置；否则
固定单播发现无法工作。
