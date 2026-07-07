# New Pico Repeatable Humble Deployment

This document defines the repeatable deployment loop for a clean Pico machine.
The target architecture is Ubuntu 20.04 focal `amd64`.

## What The Environment Bundle Owns

The Humble environment bundle owns only the platform prerequisites:

- `/opt/ros/humble`
- `ros-humble-*` marker debs for rosdep and apt visibility
- local focal rosdep rules for bundled Humble packages
- CycloneDDS runtime defaults for the fixed Orin/Pico wired topology
- Linux DDS socket buffer tuning
- smoke-test scripts

Business packages, robot model configuration, systemd bringup, and Orin Docker
compose stay in `one-stop-upgrade`.

## Clean Pico Install

Copy the generated artifact directory to the Pico and run:

```bash
cd artifacts
sudo ./install_ros2_humble.sh
source /etc/ros/source_ros2_humble_clean.bash
./verify_installed_humble_env.sh
```

The installer refuses to mix with an existing non-empty `/opt/ros/humble` or
already installed `ros-humble-*` packages. For a deliberate reinstall:

```bash
sudo apt remove -y 'ros-humble-*' ros2-humble-focal-desktop-source
sudo rm -rf /opt/ros/humble
cd artifacts
sudo ./install_ros2_humble.sh
```

## Installed DDS Files

When the artifact was built from this repository, the installer also installs:

```text
/etc/ros/cyclonedds/pico-cyclonedds.xml
/etc/ros/ros2_humble_cyclone.env
/etc/ros/source_ros2_humble_clean.bash
/etc/profile.d/ros2_humble_cyclone.sh
/etc/sysctl.d/10-ros2-dds.conf
/opt/zj_humanoid/tools/ros2_link_test.py
/opt/zj_humanoid/tools/source_ros2_humble_clean.bash
```

The profile file exports only DDS/RMW variables. Startup scripts should still
source `/etc/ros/source_ros2_humble_clean.bash` explicitly before launching
nodes, especially on machines that still load ROS 1 Noetic from a legacy global
profile.

## Orin/Pico Link Test

After the Orin Humble Docker container is running with the matching
`orin-cyclonedds.xml`, start the server on Pico:

```bash
source /etc/ros/source_ros2_humble_clean.bash
python3 /opt/zj_humanoid/tools/ros2_link_test.py server --label pico
```

Then run the client in the Orin container:

```bash
source /opt/ros/humble/setup.bash
python3 /etc/ros/cyclonedds/ros2_link_test.py client --label orin
```

The test covers reliable topics in both directions, services, and actions.

## Adding New Third-Party Dependencies

Do not install ad-hoc ROS 2 dependency debs directly on Pico. Add missing ROS 2
packages to `profiles/third_party.repos`, rebuild the unified environment, run
the downstream compile and DDS tests, then publish a new artifact version.

The release source set must be frozen by copying the generated
`source-lock.repos` to `profiles/third_party.lock.repos`.
