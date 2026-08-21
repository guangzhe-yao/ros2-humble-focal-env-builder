# ROS 2 Humble Pico 离线包产物

这个目录用于存放已经打好的 Pico 离线部署包，方便后续新机器直接离线安装。

本机历史包：

```text
ros2-humble-focal-offline-bundle_202607081603_amd64.tar.gz
```

该历史包不再推荐部署到全新 Pico。实机验证发现其中主 deb 声明了
`libasio-dev`，但旧版 `apt-root-deps.txt` 没有包含它。打包器现已修复为始终读取
主 deb 的 `Depends` / `Pre-Depends`；发布新离线包前必须用当前脚本重新生成，
不要继续分发上面的历史 tar。

历史包基础信息：

```text
Ubuntu: 20.04 focal
Architecture: amd64
ROS install prefix: /opt/ros/humble
ROS package count: 399
Marker deb count: 399
CycloneDDS: rmw_cyclonedds_cpp
Build path references: 0
apt missing deps: 0
apt deb count: 419
ELF missing shared libraries after bundled apt deps: 0
verify script: rosdep cache missing is warning-only
apt install policy: no-upgrade, refuse package removals
fixed: libspdlog.so.1/rclpy import failure and python3-packaging gap on clean Pico
fixed: ros2 bash tab completion and ros2 control pygraphviz warning
fixed: runtime bundle omits python3-rosdep2 to avoid removing existing ROS 1/Noetic packages
```

校验：

```bash
cd offline_artifacts
sha256sum -c ros2-humble-focal-offline-bundle_202607081603_amd64.tar.gz.sha256
```

重新生成开发版离线包：

```bash
INCLUDE_DEV_DEPS=1 \
EXTRA_APT_ROOT_DEPS_FILE="$PWD/profiles/pico_robot_overlay_apt_deps.txt" \
FAIL_ON_MISSING_APT_DEBS=1 \
BUILD_OFFLINE_BUNDLE=1 \
./packaging/repackage_existing_humble_artifacts.sh
```

说明：仓库根目录 `.gitignore` 默认忽略 `*.tar.gz`，避免把 180MB+ 的离线包误提交到 Git。这个目录仍然可以在本机保存实际产物。

补充：上面的历史包只是 ROS 2 Humble 运行基线包。若新 Pico 还要离线编译
`navi_ros2_sdk/src/robot`、`src/lowerlimb`、`src/upperlimb`，请用
`profiles/pico_robot_overlay_apt_deps.txt` 和需要的 vendor `.deb` 重新生成开发版
离线包。
