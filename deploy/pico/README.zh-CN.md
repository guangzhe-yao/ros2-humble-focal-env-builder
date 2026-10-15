# Humble 安装入口与可选维护工具

`install_humble_environment.sh` 会作为离线包中的 `install.sh` 发布。
用户只需在完整解压目录执行 `sudo bash install.sh`。

其余 DDS 配置、网络诊断和验证文件仅供维护者按现场需求参考，
不会由新版开发环境安装器复制到系统或自动执行。
安装器不设置固定 IP、DDS 对端、Domain ID、sysctl 或机器人服务。

例如需要诊断 DDS 时，可在明确网络配置后手动调用本目录的
`ros2_link_test.py`。不要把历史模板中的 IP 当作目标机器默认配置。
