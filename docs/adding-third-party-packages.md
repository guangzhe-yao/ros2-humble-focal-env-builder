# Adding Third-Party ROS 2 Packages

This is the verified workflow for adding ROS 2 Humble packages to the unified
Ubuntu 20.04 focal amd64 environment.

## 1. Collect Module Requirements

For every module, record:

- ROS package names used in `package.xml`.
- Upstream repository URL.
- Humble-compatible branch, tag, or commit.
- Non-ROS apt dependencies.
- Required runtime smoke test.

Do not add only the top-level repository. On focal, ROS dependencies that are
normally installed as Humble debs on jammy must also be present in the source
workspace unless they already exist in the base bundle.

## 2. Update The Development Manifest

Edit:

```text
profiles/third_party.repos
```

Add the top-level repository and all missing ROS source dependencies. Branch
names are acceptable while evaluating a new package set.

Check whether a dependency already exists in the base environment:

```bash
source ~/ros2_humble/install_deploy/setup.bash
ros2 pkg prefix <package_name>
```

If that succeeds, the package does not need to be added again unless an
intentional override is required.

## 3. Prepare Sources

When the focal build machine can reach GitHub:

```bash
mkdir -p ~/ros2_humble_source_cache
vcs import ~/ros2_humble_source_cache < profiles/third_party.repos
```

When it cannot reach GitHub, run the same import on a machine with GitHub access
and copy the entire source cache to the focal builder:

```bash
rsync -a --delete ~/ros2_humble_source_cache/ \
  nav01@172.16.11.164:~/ros2_humble_source_cache/
```

The cache must match the selected profile. Do not leave unrelated repositories
such as simulation demos in the cache.

## 4. Build The Unified Environment

On `nav01@172.16.11.164`:

```bash
cd ~/Desktop/jenkins/ros2-humble-focal-env-builder
export PATH="$HOME/.local/bin:$PATH"

SOURCE_CACHE_DIR="$HOME/ros2_humble_source_cache" \
PROFILE="$PWD/profiles/third_party.repos" \
BASE_PREFIX="$HOME/ros2_humble/install_deploy" \
WORK_DIR="$HOME/ros2_humble_unified" \
PKG_VERSION="0.3.0+$(date +%Y%m%d%H%M)" \
./scripts/build_unified_humble_env.sh
```

The script performs:

1. Focal/amd64 and tool checks.
2. A fresh copy of the known base Humble install space.
3. Source import or source-cache copy.
4. Exact source lock generation.
5. rosdep update and dependency installation.
6. Release colcon build without `--symlink-install`.
7. ROS package and rosdep smoke checks.
8. Unified deb, marker deb, installer, and rosdep-rule generation.

## 5. Inspect The Result

Artifacts are written to:

```text
~/ros2_humble_unified/package_out/artifacts
```

Check the expected files:

```bash
ls -lh ~/ros2_humble_unified/package_out/artifacts
```

Check important packages against the unified prefix:

```bash
INSTALL_PREFIX="$HOME/ros2_humble_unified/install_deploy" \
  ~/Desktop/jenkins/ros2-humble-focal-env-builder/scripts/verify_installed_humble_env.sh
```

Run module-specific tests as well. A successful colcon build is necessary but
does not prove hardware, launch files, parameters, or DDS behavior.

## 6. Test Downstream Compilation

Create a small overlay package that depends on newly added packages, then build
it against the unified prefix:

```bash
rm -rf ~/humble_downstream_compile_test
mkdir -p ~/humble_downstream_compile_test/src
source ~/ros2_humble_unified/install_deploy/setup.bash
cd ~/humble_downstream_compile_test/src

ros2 pkg create \
  --build-type ament_cmake \
  --license Apache-2.0 \
  --dependencies rclcpp <new_dependency> \
  --node-name compile_probe \
  downstream_compile_probe

cd ..
rosdep check --from-paths src --ignore-src \
  --rosdistro humble --os=ubuntu:focal
colcon build --symlink-install
```

## 7. Freeze The Verified Source Set

After build and runtime checks succeed:

```bash
cp ~/ros2_humble_unified/package_out/source-lock.repos \
  profiles/third_party.lock.repos
git add profiles/third_party.repos profiles/third_party.lock.repos
git commit -m "Add <module> dependencies to unified Humble environment"
git push origin main
```

Use `profiles/third_party.lock.repos` for release rebuilds. It contains commit
SHAs and avoids changes caused by moving upstream branches.

## 8. Deploy

Copy the complete artifact directory to a clean Ubuntu 20.04 amd64 machine:

```bash
cd artifacts
sudo ./install_ros2_humble.sh
source /opt/ros/humble/setup.bash
./verify_installed_humble_env.sh
```

For an existing older unified bundle, remove the old marker and main packages,
remove `/opt/ros/humble`, and install the new artifact set. Do not mix files from
two bundle versions.

## Verified Baseline

The workflow was tested on `nav01@172.16.11.164` with:

- Ubuntu 20.04.6 amd64.
- ROS 2 Humble Desktop source base.
- 16 third-party repositories.
- 58 third-party packages built.
- 387 total ROS packages in the unified prefix.
- 387 generated `ros-humble-*` marker debs.
- A 45 MB compressed unified deb and 432 MB extracted payload.
- No unified test-build path found in packaged text files.
- A downstream overlay depending on `rclcpp`, `hardware_interface`,
  `controller_interface`, and `control_msgs` compiled and ran successfully.
