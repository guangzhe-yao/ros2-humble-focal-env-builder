# Risks And Mitigations

This build is intentionally a source-built ROS 2 Humble environment for Ubuntu
20.04 focal amd64. It can work well for identical machines, but it is not the
same risk profile as official Humble binary packages on Ubuntu 22.04 jammy.

## Where It Can Fail

1. OS drift between machines

The package is built against Ubuntu 20.04 amd64 system libraries. If target
machines have different Ubuntu releases, mixed PPAs, or incompatible library
versions, runtime loading can fail.

Mitigation: deploy only to the same OS image family, keep `runtime-deps.txt`,
and run `deploy/pico/verify_installed_humble_env.sh` after install.

2. Absolute paths and RPATH

Source builds can embed build-machine paths in CMake files, Python entry points,
or ELF RPATH/RUNPATH.

Mitigation: build release artifacts without `--symlink-install`; package from a
fresh install prefix; let `builder/package/build_ros2_humble_bundle.sh` rewrite text
references and ELF RPATHs; verify `ros2 pkg prefix` points to `/opt/ros/humble`.

3. Upstream branch drift

Using branch names such as `humble`, `main`, or `ros2` means tomorrow's rebuild
may not be identical to today's rebuild.

Mitigation: before release, replace branch names in `profiles/*.repos` with
commit SHAs or keep the generated `source-lock.repos` with the artifact.

If the build host cannot access GitHub, create a source cache on another machine,
copy it to the focal build host, and set `SOURCE_CACHE_DIR`. Keep the cache
contents aligned with the selected profile.

4. Missing ROS source dependencies on focal

Humble upstream rosdep maps most ROS packages to Ubuntu 22.04 jammy. On focal,
`rosdep` can fail if a ROS dependency is not in the workspace and has no local
source-build marker.

Mitigation: include third-party ROS dependencies in the same `.repos` profile;
run `rosdep check --from-paths src --ignore-src --os=ubuntu:focal --rosdistro humble`.

5. Fake marker packages hiding missing files

Marker debs tell apt/rosdep a ROS package is installed. If markers were generated
without the actual package files in the install prefix, downstream builds would
resolve dependencies but fail at CMake/import time.

Mitigation: marker packages are generated only from the install prefix's ament
index; always run `ros2 pkg prefix <package>` for important packages before
release.

6. Duplicate package names

If the third-party workspace contains two packages with the same name, or tries
to replace a package that already exists in the base install prefix, results can
be confusing.

Mitigation: keep profiles curated; fail on duplicate source package names; only
override base packages deliberately and document it in the profile.

7. Toolchain mismatches

Some current third-party packages require newer tools than Ubuntu 20.04 ships.
For example, the verified `ros2_control` dependency set needed CMake 3.22+.

Mitigation: install user-level CMake via pip and export `$HOME/.local/bin` before
`colcon build`; keep tool versions recorded in build logs.

8. Python version assumptions

This focal build uses Python 3.8. Some newer ROS packages may assume Python 3.10
because official Humble binaries target jammy.

Mitigation: test Python packages in the focal build; avoid packages that require
Python 3.10-only syntax or dependencies unless they are patched.

9. Gazebo and hardware-specific packages

Gazebo, GPU, camera, and hardware driver packages often have extra non-ROS
system dependencies or vendor assumptions.

Mitigation: add them one module at a time, run package-level smoke tests, and
record required apt/system setup in the profile README.

10. Stale files from previous builds

Building repeatedly into the same prefix can leave old files behind.

Mitigation: this repository's build script creates a fresh unified install prefix
by copying the known base install space, then builds third-party packages into
that clean prefix.

## Expected User Experience

Other users should be able to compile their own overlays against the deployed
environment if all of the following are true:

- They are on Ubuntu 20.04 amd64 with the same system dependency baseline.
- They installed the generated offline environment with `sudo bash install.sh`.
- They source `/opt/ros/humble/setup.bash`.
- The release includes development tools from `dev-deps.txt` by default.
- Their own missing ROS dependencies are either already included in the bundle or
  included as source in their workspace.

This is suitable for controlled internal machines. It is not a general-purpose
replacement for official ROS 2 Humble on Ubuntu 22.04.
