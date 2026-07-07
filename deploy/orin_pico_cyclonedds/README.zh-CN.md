# Orin/Pico CycloneDDS 固定拓扑

目标拓扑：

- Orin Humble Docker：`192.168.217.100`
- Pico Ubuntu 20.04 Humble 源码环境：`192.168.217.66`
- RMW：`rmw_cyclonedds_cpp`
- ROS_DOMAIN_ID：默认 `20`
- DDS 发现：禁用 multicast，固定 unicast peers，避免 Docker/多网卡选错链路。

## Orin 启动 Humble 容器

在 Orin 上执行：

```bash
cd ~/ros2-humble-focal-env-builder/deploy/orin_pico_cyclonedds
chmod +x start_orin_humble_container.sh ros2_link_test.py
./start_orin_humble_container.sh
```

进入容器：

```bash
docker exec -it orin_humble_cyclone bash -lc 'source /opt/ros/humble/setup.bash && bash'
```

容器环境固定为：

```bash
export ROS_DOMAIN_ID=20
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file:///etc/ros/cyclonedds/orin-cyclonedds.xml
```

在 `one-stop-upgrade` 的 ROS 2 compose 中建议使用统一 anchor，而不是保留
ROS 1 的 `roscore_service` 作为环境中心。示例：

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
    network_mode: host
    ipc: host
    environment:
      <<: *ros2-env
    volumes: *ros2-volumes
```

ROS 2 没有 `roscore`，所以 service 之间不需要依赖 roscore 才能发现彼此。
但每个 ROS 2 进程必须在启动前拿到同一套 `ROS_DOMAIN_ID`、RMW 和
CycloneDDS XML。

## Pico 环境变量

在 Pico 上执行：

```bash
sudo mkdir -p /etc/ros/cyclonedds
sudo cp pico-cyclonedds.xml /etc/ros/cyclonedds/pico-cyclonedds.xml
sudo cp 10-ros2-dds.conf /etc/sysctl.d/10-ros2-dds.conf
sudo sysctl --system

source /etc/ros/source_ros2_humble_clean.bash
ros2 daemon stop
```

如果登录 shell 默认 source 了 ROS 1 Noetic，不要在同一个 shell 里直接叠加
Humble。仓库安装器会放置 `/etc/ros/source_ros2_humble_clean.bash`，它会先清掉
Noetic/Foxy 的路径和变量，再加载 Humble 与 Pico CycloneDDS 配置。

## Topic/Service/Action 冒烟测试

Pico 侧启动测试服务端：

```bash
source /etc/ros/source_ros2_humble_clean.bash
python3 ros2_link_test.py server --label pico
```

Orin 容器里启动客户端：

```bash
docker exec -it orin_humble_cyclone bash -lc '
  source /opt/ros/humble/setup.bash
  python3 /etc/ros/cyclonedds/ros2_link_test.py client --label orin
'
```

这个测试覆盖：

- `/link_test/from_server`：Pico 到 Orin 的可靠 topic。
- `/link_test/from_client`：Orin 到 Pico 的可靠 topic，并由 status service 验证 Pico 收到。
- `/link_test/ping` 和 `/link_test/status`：Orin 调 Pico service。
- `/link_test/single_joint_position`：Orin 调 Pico action，包含 feedback 和 result。

如果要反向验证 service/action，把 server 跑在 Orin 容器，client 跑在 Pico 即可。

## 运行业务节点时的原则

- 话题、服务、Action 都是 ROS 2 对外接口，底层都会走当前 RMW，即这里的 CycloneDDS。
- 连续数据和状态流用 topic，例如状态、传感器、`cmd_vel`。
- 快速请求/应答用 service，例如模式切换、一次性查询。
- 需要执行时间、反馈、取消的任务用 action，例如导航、轨迹、标定流程。
- 控制指令建议 `RELIABLE + KEEP_LAST(1)`，传感器高频流按实际带宽选择 `BEST_EFFORT` 或压缩。
- 调试通信先看 `ros2 topic info -v`，很多“看得到但收不到”是 QoS 不兼容。
