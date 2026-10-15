#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="${1:-}"
MODE="${2:---check}"
if [[ "$BUNDLE" == --check || "$BUNDLE" == --install ]]; then
  MODE="$BUNDLE"
  BUNDLE=""
fi
[[ "$MODE" == --check || "$MODE" == --install ]] || { echo 'Use --check or --install' >&2; exit 64; }

# Prefer the current combined robot delivery over the legacy base-only bundle.
if [ -z "$BUNDLE" ]; then
  BUNDLE="$(find "$SCRIPT_DIR" -maxdepth 1 -type f \
    -name 'robot-humble-focal-offline-*-amd64.tar.gz' \
    -printf '%T@ %p\n' | sort -nr | awk 'NR == 1 {sub(/^[^ ]+ /, ""); print; exit}')"
fi

if [ -z "$BUNDLE" ]; then
  latest="$SCRIPT_DIR/ros2-humble-focal-offline-bundle_latest_amd64.tar.gz"
  if [ -e "$latest" ]; then
    BUNDLE="$latest"
  else
    BUNDLE="$(find "$SCRIPT_DIR" -maxdepth 1 -type f \
      -name 'ros2-humble-focal-offline-bundle_*_amd64.tar.gz' \
      -printf '%T@ %p\n' | sort -nr | awk 'NR == 1 {sub(/^[^ ]+ /, ""); print; exit}')"
  fi
fi

if [ -z "$BUNDLE" ] || [ ! -f "$BUNDLE" ]; then
  echo "No Pico offline bundle found next to $0" >&2
  exit 1
fi

BUNDLE="$(readlink -f "$BUNDLE")"
CHECKSUM="$BUNDLE.sha256"
if [ ! -f "$CHECKSUM" ]; then
  echo "Missing checksum: $CHECKSUM" >&2
  exit 1
fi

(
  cd "$(dirname "$BUNDLE")"
  sha256sum -c "$(basename "$CHECKSUM")"
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
tar --no-same-owner -xzf "$BUNDLE" -C "$tmp_dir"

bundle_root="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)"
if [[ -x "$bundle_root/install.sh" && -x "$bundle_root/verify-installation.sh" ]]; then
  if [[ "$MODE" == --install && "$(id -u)" -ne 0 ]]; then
    sudo bash "$bundle_root/install.sh" "$MODE"
  else
    bash "$bundle_root/install.sh" "$MODE"
  fi
  if [[ "$MODE" == --install ]]; then
    bash "$bundle_root/verify-installation.sh"
  fi
  exit 0
fi
installer="$bundle_root/install_offline_humble_bundle.sh"
verifier="$bundle_root/artifacts/verify_installed_humble_env.sh"

if [ ! -x "$installer" ] || [ ! -x "$verifier" ]; then
  echo "Offline bundle is incomplete: installer or verifier is missing" >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  "$installer"
else
  sudo "$installer"
fi

"$verifier"

cat <<'EOF'

Pico ROS 2 Humble offline deployment passed.
Open a new shell or run:
  source /etc/ros/source_ros2_humble_clean.bash
EOF
