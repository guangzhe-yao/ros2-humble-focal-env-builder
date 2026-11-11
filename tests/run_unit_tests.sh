#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
for tool in bash git python3 perl file dpkg-deb dpkg-scanpackages apt-get apt-cache tar gzip; do
  command -v "$tool" >/dev/null || { echo "Missing test tool: $tool" >&2; exit 1; }
done
perl -MDpkg::Deps -e 1
git rev-parse --show-toplevel >/dev/null
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find builder deploy tests -name '*.sh' -print0)
for test in tests/test_*.sh; do
  [[ "$test" != tests/test_development_release.sh ]] || continue
  printf '\n== %s ==\n' "$test"
  bash "$test"
done
python3 -m unittest discover -s tests -p 'test_*.py'
git diff --check
echo 'Maintainer unit tests passed; no installation or hardware test was run.'
