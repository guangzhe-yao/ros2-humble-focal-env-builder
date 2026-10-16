#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required=(
  "$REPO_ROOT/builder/package_installed_pico.sh"
  "$REPO_ROOT/builder/package/build_ros2_humble_bundle.sh"
  "$REPO_ROOT/builder/package/build_offline_humble_bundle.sh"
  "$REPO_ROOT/deploy/pico/pico-cyclonedds.xml"
  "$REPO_ROOT/deploy/pico/verify_installed_humble_env.sh"
  "$REPO_ROOT/release/pico/install.sh"
)

for path in "${required[@]}"; do
  if [ ! -f "$path" ]; then
    echo "Missing required repository path: $path" >&2
    exit 1
  fi
done

for obsolete in scripts packaging offline_artifacts deploy/orin_pico_cyclonedds; do
  if [ -e "$REPO_ROOT/$obsolete" ]; then
    echo "Obsolete repository path still exists: $obsolete" >&2
    exit 1
  fi
done

# Generated DEB inventories and validation logs contain legitimate upstream
# paths; inspect repository sources, not ignored release payloads.
if git -C "$REPO_ROOT" grep --untracked --exclude-standard -nE \
    'scripts/|packaging/|offline_artifacts|deploy/orin_pico_cyclonedds' \
    -- . ':!*.repos' ':!tests/test_repository_layout.sh'; then
  echo "Obsolete path reference found" >&2
  exit 1
else
  status=$?
  [[ "$status" -eq 1 ]] || exit "$status"
fi

echo "Repository layout test passed."
