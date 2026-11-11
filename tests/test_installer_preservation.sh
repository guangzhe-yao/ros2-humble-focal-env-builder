#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
source "$REPO/deploy/pico/install_humble_environment.sh"
ROOT="$temp"
printf 'rclcpp\n' > "$ROOT/ros-packages.txt"
MODE=clean
dpkg-query() {
  if [[ "$*" == *'-L '* ]]; then
    printf '/opt/ros/humble/share/ament_index/resource_index/packages/%s\n' "$OWNED"
  elif [[ "$*" == *'ros2-humble-focal-desktop-source' && "$MODE" != fresh ]]; then
    echo installed
  elif [[ "$*" == *'ros-humble-navi-robot-msgs' && "$MODE" == marker ]]; then
    echo installed
  else
    return 1
  fi
}
OWNED=rclcpp
check_existing_installation
MODE=fresh
check_existing_installation
MODE=clean OWNED=navi_robot_msgs
if (check_existing_installation); then echo 'Business payload upgrade was allowed' >&2; exit 1; fi
OWNED=custom_controller
if (check_existing_installation); then echo 'Unknown owned payload upgrade was allowed' >&2; exit 1; fi
MODE=marker OWNED=rclcpp
if (check_existing_installation); then echo 'Legacy marker upgrade was allowed' >&2; exit 1; fi
echo 'Installer preserves old monolithic business payloads and markers.'
