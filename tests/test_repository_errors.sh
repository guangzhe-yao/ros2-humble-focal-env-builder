#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for expected in 0 1 128; do
  # grep: 1 means no matches, 0 means an obsolete path, 128 is a tool error.
  case "$expected" in 0) mock=1;; 1) mock=0;; 128) mock=128;; esac
  actual=0
  MOCK_GIT_STATUS="$mock" bash -c '
    git() { return "$MOCK_GIT_STATUS"; }
    export -f git
    bash "$1/tests/test_repository_layout.sh"
  ' bash "$REPO" >/dev/null 2>&1 || actual=$?
  [[ "$actual" -eq "$expected" ]] || {
    echo "Repository scan: expected $expected, got $actual" >&2; exit 1;
  }
done
echo 'Repository scan distinguishes no matches from Git errors.'
