#!/usr/bin/env bash
set -Eeuo pipefail
OUT="${1:?Pass an output DEB directory}"
. /etc/os-release
[[ "$VERSION_CODENAME/$(dpkg --print-architecture)" == focal/amd64 ]] || exit 65
[[ "$(/usr/xenomai/bin/xeno-config --version)" == 3.1.4 ]] || exit 65
mkdir -p "$OUT"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/DEBIAN" "$stage/usr" "$stage/etc/ld.so.conf.d"
cp -a /usr/xenomai "$stage/usr/"
printf '/usr/xenomai/lib\n' > "$stage/etc/ld.so.conf.d/zj-xenomai-userspace.conf"
printf 'Package: zj-humanoid-xenomai-userspace\nVersion: 3.1.4-1focal\nArchitecture: amd64\nMaintainer: guangzhe-yao <guangzhe-yao@users.noreply.github.com>\nDepends: libc6 (>= 2.31), libgcc-s1, libstdc++6\nDescription: Snapshot of verified Xenomai 3.1.4 userspace; matching Cobalt kernel required for hardware\n' > "$stage/DEBIAN/control"
printf '#!/bin/sh\nset -e\nldconfig\n' > "$stage/DEBIAN/postinst"
chmod +x "$stage/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$stage" "$OUT/zj-humanoid-xenomai-userspace_3.1.4-1focal_amd64.deb"
rm -rf "$stage"
stage="$(mktemp -d)"
mkdir -p "$stage/DEBIAN" "$stage/etc/ld.so.conf.d"
printf '/opt/openrobots/lib\n/opt/zj_humanoid/lib/rtipc_runtime\n/opt/zj_humanoid/lib/uplimb_runtime\n/opt/zj_humanoid/lib/logging\n' > "$stage/etc/ld.so.conf.d/zj-humanoid-platform.conf"
printf 'Package: zj-humanoid-robot-platform-deps\nVersion: 1.0.0-20261015focal\nArchitecture: amd64\nMaintainer: guangzhe-yao <guangzhe-yao@users.noreply.github.com>\nDepends: zj-humanoid-xenomai-userspace (= 3.1.4-1focal), zj-humanoid-rtipc-runtime (>= 1.4.4), zj-humanoid-uplimb-runtime (>= 1.4.3), zj-humanoid-logging, robotpkg-pinocchio (= 3.4.0), robotpkg-coal (= 3.0.1), libzmq5, libhdf5-cpp-103, libgoogle-glog0v5, python3-psutil, python3-ruamel.yaml\nDescription: Explicit missing dependency contract for the supplied Focal robot runtimes\n' > "$stage/DEBIAN/control"
printf '#!/bin/sh\nset -e\nldconfig\n' > "$stage/DEBIAN/postinst"
chmod +x "$stage/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$stage" "$OUT/zj-humanoid-robot-platform-deps_1.0.0-20261015focal_amd64.deb"
