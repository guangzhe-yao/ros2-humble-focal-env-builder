# ROS 2 Humble Focal Environment Builder

This repository manages the repeatable build flow for a source-built ROS 2
Humble desktop environment on Ubuntu 20.04 focal amd64, with curated third-party
ROS packages merged into the same deployable `/opt/ros/humble` bundle.

It is designed for the current internal deployment model: identical focal amd64
machines, no official Humble focal apt packages, and occasional curated rebuilds
when module teams add third-party ROS dependencies.

## Repository Contents

- `profiles/third_party.repos`: curated third-party source manifest.
- `scripts/build_unified_humble_env.sh`: import sources, run rosdep, build with
  colcon, verify, and produce deploy artifacts.
- `scripts/verify_installed_humble_env.sh`: smoke check for a deployed machine.
- `packaging/build_ros2_humble_bundle.sh`: Debian bundle and marker generator.
- `docs/risks-and-mitigations.md`: known risks and how to reduce them.

Generated debs, build logs, and install spaces are intentionally ignored by Git.

## Build Host Requirements

Run the build on Ubuntu 20.04 focal amd64. The known build machine is:

```text
nav01@172.16.11.164
```

Expected base ROS install space:

```text
~/ros2_humble/install_deploy
```

Install common build tools:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git curl rsync patchelf \
  python3-pip python3-vcstool python3-rosdep \
  python3-colcon-common-extensions
```

## Build A Unified Environment

```bash
cd ~/ros2-humble-focal-env-builder

PKG_VERSION="0.2.0+$(date +%Y%m%d%H%M)" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PROFILE="$PWD/profiles/third_party.repos" \
./scripts/build_unified_humble_env.sh
```

Artifacts will be written to:

```text
~/ros2_humble_unified/package_out/artifacts
```

The artifact directory contains:

- `ros2-humble-focal-desktop-source_<version>_amd64.deb`
- `ros-humble-package-markers_<version>_amd64.tar.gz`
- `rosdep-humble-focal-source-build.yaml`
- `install_ros2_humble.sh`
- `install_ros2_humble_markers.sh`
- `runtime-deps.txt`
- `dev-deps.txt`
- `third_party.repos`
- `source-lock.repos`

## Deploy

On a clean target machine:

```bash
cd artifacts
sudo ./install_ros2_humble.sh
source /opt/ros/humble/setup.bash
```

Validate:

```bash
./verify_installed_humble_env.sh
```

If the target already has an older bundle, remove it first:

```bash
sudo apt remove -y 'ros-humble-*' ros2-humble-focal-desktop-source
sudo rm -rf /opt/ros/humble
sudo ./install_ros2_humble.sh
```

## How To Add More Third-Party Packages

1. Add the repository to `profiles/third_party.repos`.
2. Add any ROS source dependencies that do not exist in the base bundle.
3. Build once with branch names while evaluating.
4. Before release, pin `version` fields to commit SHAs or keep the generated
   `source-lock.repos` with the release artifact.
5. Run `scripts/build_unified_humble_env.sh`.
6. Verify important packages with `ros2 pkg prefix <name>` and module smoke
   tests.

## Notes

The focal Humble build is not official ROS packaging. It is a controlled internal
environment bundle. Read `docs/risks-and-mitigations.md` before promoting a
bundle to wider use.
