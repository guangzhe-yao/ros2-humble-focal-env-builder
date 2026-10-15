#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="${1:-$ROOT/ros2-humble-focal-offline-bundle_latest_amd64.tar.gz}"
[[ $# -le 1 && -f "$BUNDLE" ]] || { echo "Usage: sudo bash $0 [environment.tar.gz]" >&2; exit 64; }
BUNDLE="$(readlink -f "$BUNDLE")"
(cd "$(dirname "$BUNDLE")"; sha256sum -c "$(basename "$BUNDLE").sha256")
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
tar --no-same-owner -xzf "$BUNDLE" -C "$temp"
mapfile -t roots < <(find "$temp" -mindepth 1 -maxdepth 1 -type d)
[[ ${#roots[@]} -eq 1 && -f "${roots[0]}/install.sh" ]] || {
  echo 'Invalid Humble environment release' >&2; exit 1;
}
if [[ "$EUID" -eq 0 ]]; then
  bash "${roots[0]}/install.sh"
else
  sudo bash "${roots[0]}/install.sh"
fi
