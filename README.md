# ROS 2 Humble Focal Environment Builder

[English](README.md) | [简体中文](README.zh-CN.md)

This repository manages the repeatable build flow for a source-built ROS 2
Humble desktop environment on Ubuntu 20.04 focal amd64, with curated third-party
ROS packages merged into the same deployable `/opt/ros/humble` bundle.

It is designed for the current internal deployment model: identical focal amd64
machines, no official Humble focal apt packages, and occasional curated rebuilds
when module teams add third-party ROS dependencies.

## Repository Contents

- `profiles/third_party.repos`: curated third-party source manifest.
- `profiles/third_party.lock.repos`: exact commits from the latest verified
  unified build.
- `profiles/ros2_humble.repos`: upstream ROS 2 Humble source manifest used by
  the clean-machine bootstrap.
- `scripts/bootstrap_humble_focal_env.sh`: bootstrap a clean Pico/focal amd64
  machine from source, then build artifacts and install `/opt/ros/humble`.
- `scripts/bootstrap_pico_humble_env.sh`: Pico entrypoint with the validated
  GitHub proxy and 2-worker defaults, then delegates to the generic bootstrap.
- `scripts/build_unified_humble_env.sh`: import sources, run rosdep, build with
  colcon, verify, and produce deploy artifacts.
- `scripts/verify_installed_humble_env.sh`: smoke check for a deployed machine.
- `packaging/build_ros2_humble_bundle.sh`: Debian bundle and marker generator.
- `docs/risks-and-mitigations.md`: known risks and how to reduce them.
- `docs/focal-build-host-network.md`: tested NetworkManager settings for the
  focal build host.
- `docs/new-pico-repeatable-deploy.md`: repeatable clean-Pico install loop for
  the Humble prerequisite environment.
- `docs/end-to-end-workflow.zh-CN.md`: Chinese end-to-end workflow from a local
  non-ROS development machine to the Focal builder and Pico/Orin targets.
- `deploy/orin_pico_cyclonedds`: CycloneDDS config, Orin Docker startup, and
  topic/service/action smoke tests for the fixed Orin/Pico wired topology.
- `tests/controller_interface_smoke`: custom `controller_interface` plugin smoke
  test used after installing the unified bundle.

Generated debs, build logs, and install spaces are intentionally ignored by Git.

## Orin/Pico Multi-Machine DDS

The current fixed robot topology is:

- Orin wired IP: `192.168.217.100`
- Pico wired IP: `192.168.217.66`
- Orin Humble image:
  `10.51.33.201:30002/navi_project/sensor:22CUDA_humble`
- RMW: `rmw_cyclonedds_cpp`
- Discovery: multicast disabled, static unicast peers.

See:

```text
deploy/orin_pico_cyclonedds/README.zh-CN.md
```

The included smoke test validates topics, services, and actions in both
directions. RMW selection is per process, so already-running ROS 2 nodes must be
restarted with the CycloneDDS environment to join this topology.

Generated artifacts include the `deploy/orin_pico_cyclonedds` assets. On Pico,
`install_ros2_humble.sh` installs the CycloneDDS XML, DDS sysctl tuning, a
reusable ROS 2 environment file, and the link-test tool.

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

## Bootstrap A Clean Pico From Source

On a clean Ubuntu 20.04 amd64 Pico, clone this repository and run:

```bash
cd /home/nav01/Public/ros2-humble-focal-env-builder

./scripts/bootstrap_pico_humble_env.sh
```

The script imports the upstream Humble source checkout from
`profiles/ros2_humble.repos`, builds the base install space, merges
`profiles/third_party.lock.repos`, creates deploy artifacts, and installs
`/opt/ros/humble`. Edit `profiles/third_party.repos` when evaluating new
third-party packages, then promote the generated `source-lock.repos` after
validation.

## Build A Unified Environment

```bash
cd ~/ros2-humble-focal-env-builder

PKG_VERSION="0.2.0+$(date +%Y%m%d%H%M)" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PROFILE="$PWD/profiles/third_party.repos" \
./scripts/build_unified_humble_env.sh
```

For a reproducible rebuild of the currently verified package set, use:

```bash
PROFILE="$PWD/profiles/third_party.lock.repos" \
PKG_VERSION="0.2.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

If the focal build machine cannot access GitHub, prepare a source cache on a
machine with GitHub access and copy it to the build machine. Then run:

```bash
SOURCE_CACHE_DIR="$HOME/ros2_humble_source_cache" \
COLCON_CMAKE_ARGS="-DCMAKE_DISABLE_FIND_PACKAGE_Doxygen=TRUE" \
PKG_VERSION="0.2.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

The cache directory must contain exactly the repositories represented by the
selected profile. The generated `source-lock.repos` records their actual commit
SHAs. Disabling Doxygen also prevents RSL's documentation target from
downloading a CSS file during an otherwise offline build.

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
- `verify_installed_humble_env.sh`

## Deploy

On a clean target machine:

```bash
cd artifacts
sudo ./install_ros2_humble.sh
source /etc/ros/source_ros2_humble_clean.bash
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

See `docs/adding-third-party-packages.md` for the tested end-to-end workflow.

In short: update `profiles/third_party.repos`, include missing ROS source
dependencies, build and test, then promote the generated `source-lock.repos` to
`profiles/third_party.lock.repos`.

## Notes

The focal Humble build is not official ROS packaging. It is a controlled internal
environment bundle. Read `docs/risks-and-mitigations.md` before promoting a
bundle to wider use.
