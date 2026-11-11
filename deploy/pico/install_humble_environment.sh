#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_existing_installation() {
  local owned path name obsolete
  # An old monolithic DEB may own application files. Upgrading would delete them.
  if [[ "$(dpkg-query -W -f='${db:Status-Status}' ros2-humble-focal-desktop-source 2>/dev/null || true)" == installed ]]; then
    owned="$(dpkg-query -L ros2-humble-focal-desktop-source)"
    while IFS= read -r path; do
      case "$path" in
        /opt/ros/humble/share/ament_index/resource_index/packages/*)
          name="${path##*/}"
          grep -Fxq "$name" "$ROOT/ros-packages.txt" || {
            echo "Refusing upgrade: installed base owns excluded ROS package $name; migrate it separately first" >&2
            exit 65
          }
          ;;
      esac
    done <<< "$owned"
  fi
  for obsolete in ros-humble-navi-robot-msgs ros-humble-robot-nodes-py; do
    if [[ "$(dpkg-query -W -f='${db:Status-Status}' "$obsolete" 2>/dev/null || true)" == installed ]]; then
      echo "Refusing upgrade with legacy business marker $obsolete; manual migration required" >&2
      exit 65
    fi
  done
}

installation_roots() {
  local root installed
  while IFS= read -r root; do
    [[ -n "$root" ]] || continue
    # Do not request upgrades of already installed, unversioned system roots.
    # APT still enforces all transitive version constraints of the new ROS/tools.
    if [[ "$root" != *=* ]]; then
      installed="$(dpkg-query -W -f='${db:Status-Status}' "$root" 2>/dev/null || true)"
      [[ "$installed" != installed ]] || continue
    fi
    printf '%s\n' "$root"
  done < "$ROOT/root-packages.txt"
}

main() {
  [[ $# -eq 0 ]] || { echo "Usage: sudo bash $0" >&2; exit 64; }
  [[ "$EUID" -eq 0 ]] || { echo "Run with sudo: sudo bash $0" >&2; exit 77; }
  . /etc/os-release
  [[ "$ID/$VERSION_CODENAME/$(dpkg --print-architecture)" == ubuntu/focal/amd64 ]] || {
    echo 'This environment requires Ubuntu 20.04 amd64' >&2; exit 65;
  }
  (cd "$ROOT"; sha256sum --quiet -c SHA256SUMS)
  check_existing_installation
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
  mapfile -t roots < <(installation_roots)
  apt-get "${opts[@]}" -s --no-remove --no-install-recommends install "${roots[@]}"
  DEBIAN_FRONTEND=noninteractive apt-get "${opts[@]}" -y --no-remove \
    --no-install-recommends install "${roots[@]}"
  dpkg --audit
  echo 'Humble development environment installed. Run: source /opt/ros/humble/setup.bash'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
