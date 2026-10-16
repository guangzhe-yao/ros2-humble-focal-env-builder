# ROS 2 Humble Focal Development Environment

[简体中文](README.zh-CN.md)

Build and deliver an offline ROS 2 Humble development environment for Ubuntu
20.04 amd64. This repository owns the ROS underlay and generic development
dependencies, not robot applications or system-provided hardware runtimes.

Included: upstream ROS packages, ros2_control, RViz2, interface generation,
C/C++ compilers, CMake, colcon, Python/pip/venv, vcstool and development libraries.
Excluded: robot-state, lowerlimb, upperlimb interfaces, vendor runtime libraries,
robot SDKs and Xenomai userspace/kernel. Existing system components are not managed.

## Install

Extract the complete release archive and run:

```bash
sudo bash install.sh
source /opt/ros/humble/setup.bash
```

There is no check mode. Installation uses the bundled local apt repository and
does not erase the ROS prefix, install business DEBs or start robot services.
See [offline installation](deploy/pico/README_OFFLINE.zh-CN.md).

## Build A Release

```bash
SOURCE_PREFIX=/path/to/clean/humble/install bash builder/package_installed_pico.sh
```

The staged prefix is validated against
`profiles/humble-environment-packages.txt`. Mixed application install spaces
are rejected. Update the allowlist deliberately when adding upstream packages.
Development dependencies are included by default. Archives and checksums are
written under `release/pico/`; binary payloads are not committed to Git.

See [build and release guide](docs/build-release-deploy.zh-CN.md).
Maintainer tests include a network-disabled clean install and a real colcon
build of C++ code plus generated message interfaces; tests are not an installation step.

Builds create candidates without overwriting versions or promoting `latest`.
Run `bash tests/run_unit_tests.sh` for non-installing maintainer regression tests.
See the [quality contract](docs/quality-contract.zh-CN.md) for acceptance criteria
and the separate human review required before promoting a release.
