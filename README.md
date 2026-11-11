# Pico ROS 2 Humble Offline Development Environment

[中文说明](README.zh-CN.md)

Build and package upstream ROS 2 Humble for Ubuntu 20.04 Focal amd64, with
offline runtime and development dependencies. This is a Focal source-built
distribution, not the official Jammy binary distribution.

Copy the single self-extracting installer to the Pico and run:

```bash
sudo bash ros2-humble-focal-offline-bundle_20261111dev3_amd64.run
source /opt/ros/humble/setup.bash
```

No customer nodes, messages, robot descriptions, vendor runtimes, SDKs or Xenomai
are included. Existing ROS 1 and application workspaces are not managed here.
The .run verifies its embedded archive and invokes the existing install.sh;
it is a software installer, not firmware. No separate archive extraction is needed.
An old base DEB that owns application files blocks upgrades until those files
are migrated separately. The installer never removes application markers.

Configuration lives in `profiles/`: required/full ROS package lists,
runtime/development APT roots, upstream source revisions and ROS 1 migration
mappings. Every candidate contains an actual DEB inventory with hashes and a
configuration snapshot. Unknown binary provenance stays explicitly unknown.

Run `bash tests/run_unit_tests.sh` for maintainer regression tests.
Release acceptance additionally installs in a disposable offline Focal
container and compiles C++, custom messages and a controller plugin.
Candidates never replace existing releases or promote themselves to latest.
See the Chinese README for the directory layout and build/release workflow.
