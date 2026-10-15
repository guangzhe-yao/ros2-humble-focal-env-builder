# Robot And Lowerlimb Delivery

The base underlay must not own `navi_robot_msgs` or `robot_nodes_py`. These were
business packages accidentally included in the earlier source-built environment.
Base packaging now removes those staged files before generating apt markers.
It never prunes the live `/opt/ros/humble` prefix.

The new combined delivery entrypoint is `builder/package_robot_delivery.sh`.
Provide rebuilt base artifacts and colon-separated DEB directories using
`ARTIFACT_DIR` and `EXTRA_APT_DEBS_DIR`. Include main DEB, extracted marker DEBs,
robot DEBs, lowerlimb DEBs and original supplier DEBs. Supply previously downloaded
Ubuntu DEBs separately through `CACHED_APT_DEBS_DIR`; these are available to the
solver but do not become additional root dependencies.
The original supplier package bytes and versions are preserved.

The resulting `install.sh` defaults to `--check`; `--install` requires root.
It uses only a private local file-based apt source, verifies SHA256 checksums,
simulates the transaction, and rejects unrelated package removals. Only the two
obsolete business markers may be removed. It does not remove `/opt/ros/humble`,
start services, permit automatic downgrades, or overwrite calibration files.

`root-packages.txt` pins all ROS/vendor packages. Actual package `Depends` remain
visible with `apt-cache depends`; `apt list --installed` lists installed names
and versions, not the dependency graph. Standard ROS marker packages continue
to depend on the exact base bundle version; business packages own their files.
Marker versions now include the base bundle version so apt actually upgrades
their dependency metadata when the base is upgraded.

The supplied runtime DEBs have no Depends metadata. A separate platform dependency
package declares Pinocchio 3.4.0, Coal 3.0.1, logging and system libraries without
rewriting supplier packages. The existing Xenomai 3.1.4 userspace is snapshotted
as its own DEB. This is NOT a kernel installation: hardware still requires the
matching Cobalt kernel, CPU isolation and machine-specific SDK configuration.

Offline acceptance requires an install in a disposable Focal environment with
network disabled, not just apt simulation on an already provisioned machine.
Runtime and hardware commissioning remain separate acceptance stages.

## Verified Release

`release/pico/robot-humble-focal-offline-20261015-amd64.tar.gz` contains 1102
DEBs, with 420 exact ROS/vendor root package versions. The base version is
`0.3.2+20261015`. It is a corrected repack of the existing source-built underlay,
not a claim that all upstream ROS sources were rebuilt in this session.
Robot-state and lowerlimb business binaries were rebuilt on the Focal target.

A fresh `ubuntu:20.04` Docker container with `--network none` successfully
installed the bundle (926 new packages, one base-image package upgrade, no
removals). `dpkg --audit`, ROS package prefix checks, Python message/native
type-support imports and key executable/plugin linkage checks passed. No robot
control nodes were started. The final archive adds deployment documentation and
the same verification script; its hashes are recorded in the release manifest.

On Pico `172.16.10.129`, the two specified upperlimb DEBs and then the complete
new environment were installed. Only the two obsolete ROS business markers
were removed; existing Noetic packages and vendor runtime versions were kept.
After explicit operator authorization, `sdk_autostart.service` and
`zj_humanoid.service` were stopped, and the remaining EtherCAT manager received
SIGTERM. No robot-control process remained before installation.
Package audit, interface imports, package ownership and key dynamic-library
checks passed on the target too. Services remain stopped; boot enablement was
not changed. No SDK restart, motion, calibration or power-off was performed.
The original base archive and pre-upgrade package inventory remain in
`/home/nav01/module_delivery_20261015` on the target.

For another build, reuse the released `apt_debs` as `CACHED_APT_DEBS_DIR` and
provide newly rebuilt base/marker/module/vendor DEBs through
`EXTRA_APT_DEBS_DIR`. The cache includes the concrete `automake` provider for
Focal's virtual `automake-1.16` dependency. Original supplier DEBs stay unchanged.
The local apt index now uses `dpkg-scanpackages` (from `dpkg-dev`), avoiding
malformed records caused by trailing blank lines in supplier control files.

The release does not contain a disk image, matching Xenomai kernel or model SDK.
The archive is kept outside Git; source repositories do not redistribute the
supplier DEBs in their commit history.
