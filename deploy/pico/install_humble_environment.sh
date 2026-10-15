#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -eq 0 ]] || { echo "Usage: sudo bash $0" >&2; exit 64; }
[[ "$EUID" -eq 0 ]] || { echo "Run with sudo: sudo bash $0" >&2; exit 77; }
. /etc/os-release
[[ "$VERSION_CODENAME/$(dpkg --print-architecture)" == focal/amd64 ]] || {
  echo 'This environment requires Ubuntu 20.04 amd64' >&2; exit 65;
}
(cd "$ROOT"; sha256sum --quiet -c SHA256SUMS)
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/lists/partial" "$temp/parts" "$temp/archives/partial"
printf 'deb [trusted=yes] file:%s/apt_debs ./\n' "$ROOT" > "$temp/sources.list"
opts=(-o "Dir::Etc::sourcelist=$temp/sources.list"
      -o "Dir::Etc::sourceparts=$temp/parts"
      -o "Dir::State::Lists=$temp/lists"
      -o "Dir::Cache::archives=$temp/archives"
      -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache=
      -o APT::Sandbox::User=root -o Acquire::Languages=none)
apt-get "${opts[@]}" update
mapfile -t roots < "$ROOT/root-packages.txt"
# These empty markers belong to the obsolete base, not actual business DEBs.
for obsolete in ros-humble-navi-robot-msgs ros-humble-robot-nodes-py; do
  if [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$obsolete" 2>/dev/null || true)" == ii* ]]; then
    dpkg --remove "$obsolete"
  fi
done
DEBIAN_FRONTEND=noninteractive apt-get "${opts[@]}" -y --no-remove \
  --no-install-recommends install "${roots[@]}"
dpkg --audit
echo 'Humble development environment installed. Run: source /opt/ros/humble/setup.bash'
