#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use upstream URLs unless the maintainer explicitly configures a mirror.
export GIT_INSTEADOF_GITHUB_PREFIX="${GIT_INSTEADOF_GITHUB_PREFIX:-}"
export COLCON_PARALLEL_WORKERS="${COLCON_PARALLEL_WORKERS:-2}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$COLCON_PARALLEL_WORKERS}"

exec "$SCRIPT_DIR/bootstrap_humble_focal_env.sh" "$@"
