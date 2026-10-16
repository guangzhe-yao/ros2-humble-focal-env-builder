#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

ARTIFACT_DIR="$TEST_ROOT/artifacts"
OUT_DIR="$TEST_ROOT/out"
BUNDLE_NAME="test-bundle"
PKG_ARCH="$(dpkg --print-architecture)"
mkdir -p "$ARTIFACT_DIR" "$OUT_DIR/$BUNDLE_NAME"

printf '%s\n' bash > "$ARTIFACT_DIR/runtime-deps.txt"

PKGROOT="$TEST_ROOT/pkgroot"
mkdir -p "$PKGROOT/DEBIAN"
cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: ros2-humble-focal-desktop-source
Version: 1.0.0
Section: misc
Priority: optional
Architecture: $PKG_ARCH
Maintainer: test <test@example.com>
Depends: bash, libasio-dev (>= 1.10), libfoo-dev | libfoo-compat
Description: dependency collection fixture
EOF

dpkg-deb --build --root-owner-group "$PKGROOT" \
  "$ARTIFACT_DIR/ros2-humble-focal-desktop-source_1.0.0_${PKG_ARCH}.deb" >/dev/null

# shellcheck source=../builder/package/build_offline_humble_bundle.sh
source "$REPO_ROOT/builder/package/build_offline_humble_bundle.sh"
collect_root_deps

grep -Fxq bash "$DEPS_ROOT_FILE"
grep -Fxq libasio-dev "$DEPS_CANDIDATES_FILE"
grep -Fxq libfoo-dev "$DEPS_CANDIDATES_FILE"
grep -Fxq libfoo-compat "$DEPS_CANDIDATES_FILE"
if grep -Eq '^lib(asio|foo)' "$DEPS_ROOT_FILE"; then
  echo 'DEB dependencies must not be promoted into mandatory roots' >&2
  exit 1
fi

apt-cache() {
  [[ "$1" == policy ]] || return 1
  printf '  Candidate: (none)\n'
}
resolve_apt_closure
cmp "$DEPS_CANDIDATES_FILE" "$DEPS_CLOSURE_FILE"

echo "Offline bundle dependency collection test passed."
