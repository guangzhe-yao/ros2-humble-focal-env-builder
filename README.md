# ROS 2 Humble Focal Pico Environment Builder

[简体中文](README.zh-CN.md)

This repository builds, packages, deploys, and verifies ROS 2 Humble for Ubuntu
20.04 focal amd64 Pico machines. Orin runs Ubuntu 22.04 with an existing Docker
environment and is intentionally outside this repository's deployment scope.

## Current Robot Release

The 2026-10-15 combined offline release uses base `0.3.2+20261015` and includes
robot-state, lowerlimb and the specified vendor dependencies. See the
[release manifest](release/pico/robot-delivery-20261015.json) and
[installation guide](deploy/pico/robot_delivery_README.md).
The archive is delivered separately under `release/pico/`, not committed to Git.
`bash release/pico/install.sh --check` selects this newer bundle;
`bash release/pico/install.sh --install` installs it and verifies package linkage.

## Layout

```text
builder/                 build and packaging entrypoints
builder/package/         low-level deb and offline repository builders
deploy/pico/             Pico DDS defaults, shell environment, and verification
profiles/                source locks and overlay apt dependency lists
release/pico/            final offline handoff directory and one-command installer
tests/                   packaging and controller interface smoke tests
docs/                    maintenance and deployment documentation
```

## Package a verified Pico

Run this on Ubuntu 20.04 amd64 after `/opt/ros/humble` passes verification:

```bash
./builder/package_installed_pico.sh
```

The versioned tarball and SHA256 file are written to `release/pico/`.

## Deploy another Pico offline

Copy the complete `release/pico/` directory to the target and run:

```bash
cd release/pico
./install.sh
```

For the new combined release this defaults to a check only; use `--install`
after stopping robot control for maintenance. The legacy base-only fallback
retains its old installation behavior.

The deployment machine does not need network access. The bundle may be launched
from any directory; it installs to `/opt/ros/humble` and requires Ubuntu 20.04
focal amd64.

See [the Chinese build and deployment guide](docs/build-release-deploy.zh-CN.md)
for the complete workflow.
