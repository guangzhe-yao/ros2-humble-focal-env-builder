# Pico 离线环境安装包

新版本只交付一个自解压 .run 安装文件，SHA256 和 JSON 文件仅供维护者审核，不是第二个安装入口。

当前候选：

```bash
sudo bash ros2-humble-focal-offline-bundle_20261111dev3_amd64.run
source /opt/ros/humble/setup.bash
```

适用于 Ubuntu 20.04 amd64。无需手动解压，不联网安装，不刷系统、内核或驱动。
内置 404 个上游 ROS 包，包含 joy_teleop；共 1038 个 DEB，约 332 MiB。
默认不含 Gazebo，不包含客户业务包、SDK、供应方 runtime 或 Xenomai。

旧基础 DEB 若拥有 navi_robot_msgs/robot_nodes_py 等业务文件，安装器拒绝升级并保留现场。
业务迁移不是本安装包的职责，不能删除 marker 或清空 ROS 前缀绕过保护。
本次指定 Pico 已按用户明确授权清退这两个旧业务包，未备份；这是一次性维护操作，
不是安装器默认行为。新版避免主动升级已有系统根依赖，仍由 APT 检查实际版本约束。

候选不自动提升 latest。最终验收状态与限制见 humble-development-20261111.json；
测试通过也不代表机器人控制、GUI 或人工发布审核通过。

历史 20261015dev1 归档及旧 latest 链接按保留旧版本的约定保持原样，未覆盖、未删除。
已发现该历史包存在未登记业务消息残留和 libdw1 缺失，不应再把它当作本轮纯上游环境交付。
新版本 tar.gz 只留在 package_out 中作为构建中间件，不在此处另行发布。
20261111dev1 已被 dev3 替代；中间候选 dev2 因系统依赖版本固定过严而未通过全新容器安装，
不得使用。历史候选保留用于追溯，当前交付仅选择上述 dev3。
