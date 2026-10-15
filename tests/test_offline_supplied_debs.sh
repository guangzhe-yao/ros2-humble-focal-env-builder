#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
export ARTIFACT_DIR="$TEST_ROOT/artifacts" OUT_DIR="$TEST_ROOT/out"
export BUNDLE_NAME=test-bundle
export EXTRA_APT_DEBS_DIR="$TEST_ROOT/vendor"
export CACHED_APT_DEBS_DIR="$TEST_ROOT/cache"
mkdir -p "$ARTIFACT_DIR" "$EXTRA_APT_DEBS_DIR" "$CACHED_APT_DEBS_DIR"
printf 'bash\n' > "$ARTIFACT_DIR/runtime-deps.txt"
make_fixture() {
  local name="$1" destination="$2" provides="${3:-}"
  mkdir -p "$TEST_ROOT/$name/DEBIAN"
  printf 'Package: %s\nVersion: 1.0\nArchitecture: all\nMaintainer: Test <test@example.com>\nDescription: offline test fixture\n' "$name" > "$TEST_ROOT/$name/DEBIAN/control"
  if [[ -n "$provides" ]]; then
    printf 'Provides: %s\n' "$provides" >> "$TEST_ROOT/$name/DEBIAN/control"
  fi
  printf '\n' >> "$TEST_ROOT/$name/DEBIAN/control"
  dpkg-deb --build --root-owner-group "$TEST_ROOT/$name" "$destination/$name.deb" >/dev/null
}
make_fixture local-vendor "$EXTRA_APT_DEBS_DIR" 'virtual-runtime (= 1.0)'
make_fixture cached-system "$CACHED_APT_DEBS_DIR"
source "$REPO_ROOT/builder/package/build_offline_humble_bundle.sh"
mkdir -p "$APT_DEBS_DIR"
collect_root_deps
grep -Fxq local-vendor "$DEPS_ROOT_FILE"
if grep -Fxq cached-system "$DEPS_ROOT_FILE"; then
  echo 'Cached packages must not become roots' >&2
  exit 1
fi
printf 'local-vendor\nvirtual-runtime\ncached-system:any\n' > "$DEPS_CLOSURE_FILE"
apt-cache() { echo 'Unexpected apt-cache lookup for supplied dependency' >&2; return 1; }
export FAIL_ON_MISSING_APT_DEBS=1
download_apt_debs
[[ ! -s "$MISSING_DEPS_FILE" ]]
[[ "$(find "$APT_DEBS_DIR" -name '*.deb' | wc -l)" -eq 2 ]]
write_apt_repo_index
awk 'BEGIN {RS=""} {if ($0 !~ /(^|\n)Package:/ || $0 !~ /(^|\n)Filename:/) exit 1; count++} END {if (count != 2) exit 1}' "$APT_DEBS_DIR/Packages"
echo 'Offline supplied package/provider/cache test passed.'
