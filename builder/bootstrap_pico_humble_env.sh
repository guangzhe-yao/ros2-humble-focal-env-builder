#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pico deployment defaults. Keep these in this wrapper instead of hard-coding
# them in the generic bootstrap so other build hosts can use direct GitHub.
export GIT_INSTEADOF_GITHUB_PREFIX="${GIT_INSTEADOF_GITHUB_PREFIX:-https://gh-proxy.com/https://github.com/}"
export COLCON_PARALLEL_WORKERS="${COLCON_PARALLEL_WORKERS:-2}"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$COLCON_PARALLEL_WORKERS}"

exec "$SCRIPT_DIR/bootstrap_humble_focal_env.sh" "$@"
