#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
export ARTIFACT_DIR="$temp/artifacts" OUT_DIR="$temp/out" BUNDLE_NAME=contract-test
mkdir -p "$ARTIFACT_DIR" "$temp/pkg/DEBIAN" "$temp/markers"
printf 'Package: ros2-humble-focal-desktop-source\nVersion: 1.0\nArchitecture: amd64\nMaintainer: Test <test@example.com>\nDescription: fixture\n' > "$temp/pkg/DEBIAN/control"
base="$ARTIFACT_DIR/ros2-humble-focal-desktop-source_1.0_amd64.deb"
markers="$ARTIFACT_DIR/ros-humble-package-markers_1.0_amd64.tar.gz"
dpkg-deb --build --root-owner-group "$temp/pkg" "$base" >/dev/null
tar -czf "$markers" -C "$temp/markers" .
touch "$ARTIFACT_DIR/runtime-deps.txt" "$ARTIFACT_DIR/dev-deps.txt"
source "$REPO/builder/package/build_offline_humble_bundle.sh"
reject() {
  if ( "$@" ) > "$temp/rejected.log" 2>&1; then
    echo "Expected rejection: $*" >&2; exit 1
  fi
}
require_artifacts
cp "$base" "$ARTIFACT_DIR/ros2-humble-focal-desktop-source_2.0_amd64.deb"
reject require_artifacts
rm "$ARTIFACT_DIR/ros2-humble-focal-desktop-source_2.0_amd64.deb"
mv "$markers" "$ARTIFACT_DIR/ros-humble-package-markers_2.0_amd64.tar.gz"
reject require_artifacts
mv "$ARTIFACT_DIR/ros-humble-package-markers_2.0_amd64.tar.gz" "$markers"
rm "$ARTIFACT_DIR/dev-deps.txt"
reject require_artifacts
touch "$ARTIFACT_DIR/dev-deps.txt"

prepare_bundle_root
printf 'preserve\n' > "$BUNDLE_ROOT/sentinel"
reject prepare_bundle_root
[[ "$(<"$BUNDLE_ROOT/sentinel")" == preserve ]]
ln -s reviewed.tar.gz "$OUT_DIR/ros2-humble-focal-offline-bundle_latest_amd64.tar.gz"
make_tarball
(cd "$OUT_DIR" && sha256sum -c "$BUNDLE_NAME.tar.gz.sha256")
reject make_tarball
[[ "$(readlink "$OUT_DIR/ros2-humble-focal-offline-bundle_latest_amd64.tar.gz")" == reviewed.tar.gz ]]
(
  BUNDLE_NAME=failed BUNDLE_ROOT="$OUT_DIR/failed"
  mkdir "$BUNDLE_ROOT"
  tar() { return 42; }
  reject make_tarball
  [[ ! -e "$BUNDLE_ROOT.tar.gz" ]]
  [[ -z "$(find "$OUT_DIR" -maxdepth 1 -name '.bundle.*' -print)" ]]
)
(
  BUNDLE_NAME=concurrent BUNDLE_ROOT="$OUT_DIR/concurrent"
  mkdir "$BUNDLE_ROOT"
  tar() {
    command tar "$@"
    printf 'concurrent output\n' > "$BUNDLE_ROOT.tar.gz"
  }
  reject make_tarball
  [[ "$(<"$BUNDLE_ROOT.tar.gz")" == 'concurrent output' ]]
)
mkdir -p "$temp/keep"
touch "$temp/keep/sentinel"
(
  BUNDLE_NAME=../keep BUNDLE_ROOT="$OUT_DIR/../keep"
  reject prepare_bundle_root
)
[[ -f "$temp/keep/sentinel" ]]
(
  BUNDLE_NAME=linked BUNDLE_ROOT="$OUT_DIR/linked"
  ln -s "$temp/keep" "$BUNDLE_ROOT"
  reject prepare_bundle_root
)
[[ -f "$temp/keep/sentinel" ]]
(
  BUNDLE_NAME=existing BUNDLE_ROOT="$OUT_DIR/existing"
  printf 'preserve\n' > "$BUNDLE_ROOT.tar.gz"
  reject prepare_bundle_root
  [[ "$(<"$BUNDLE_ROOT.tar.gz")" == preserve ]]
)
echo 'Offline artifact and destination contract tests passed.'
