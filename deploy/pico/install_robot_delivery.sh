#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:---check}"
[[ "$mode" == --check || "$mode" == --install ]] || { echo 'Use --check or --install' >&2; exit 64; }
. /etc/os-release
[[ "$VERSION_CODENAME/$(dpkg --print-architecture)" == focal/amd64 ]] || exit 65
[[ "$mode" != --install || "$EUID" -eq 0 ]] || { echo 'Installation requires root' >&2; exit 77; }
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
for obsolete in ros-humble-navi-robot-msgs ros-humble-robot-nodes-py; do
  if [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$obsolete" 2>/dev/null || true)" == ii* ]]; then
    roots+=("$obsolete-")
  fi
done
apt-get "${opts[@]}" -s --no-install-recommends install "${roots[@]}" > "$temp/plan"
cat "$temp/plan"
while read -r removed; do
  case "$removed" in ros-humble-navi-robot-msgs|ros-humble-robot-nodes-py) ;;
    *) echo "Refusing unrelated removal: $removed" >&2; exit 1;; esac
done < <(awk '/^Remv / {print $2}' "$temp/plan")
if [[ "$mode" == --install ]]; then
  # No allow-downgrades and no service launch: only the checked package transaction.
  DEBIAN_FRONTEND=noninteractive apt-get "${opts[@]}" -y --no-install-recommends install "${roots[@]}"
  dpkg --audit
fi
