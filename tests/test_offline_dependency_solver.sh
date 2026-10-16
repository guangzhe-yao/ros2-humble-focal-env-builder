#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
export ARTIFACT_DIR="$temp/artifacts" OUT_DIR="$temp/out" BUNDLE_NAME=solver-test
source "$REPO/builder/package/build_offline_humble_bundle.sh"
mkdir -p "$ARTIFACT_DIR" "$APT_DEBS_DIR"
touch "$ARTIFACT_DIR/runtime-deps.txt" "$ARTIFACT_DIR/dev-deps.txt"
make_deb() {
  local name="$1" version="$2" depends="${3:-}" predepends="${4:-}"
  mkdir -p "$temp/pkg/DEBIAN"
  printf 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: Test <test@example.com>\nDescription: solver fixture\n' "$name" "$version" > "$temp/pkg/DEBIAN/control"
  [[ -z "$depends" ]] || printf 'Depends: %s\n' "$depends" >> "$temp/pkg/DEBIAN/control"
  [[ -z "$predepends" ]] || printf 'Pre-Depends: %s\n' "$predepends" >> "$temp/pkg/DEBIAN/control"
  dpkg-deb --build --root-owner-group "$temp/pkg" "$APT_DEBS_DIR/${name}_${version}_amd64.deb" >/dev/null
}
base=ros2-humble-focal-desktop-source
make_deb "$base" 1.0 'unit-missing (>= 9) | unit-provider (>= 2)' unit-pre
cp "$APT_DEBS_DIR/${base}_1.0_amd64.deb" "$ARTIFACT_DIR/"
make_deb unit-provider 2
make_deb unit-pre 1
collect_root_deps
grep -Fxq unit-missing "$DEPS_CANDIDATES_FILE"
grep -Fxq unit-provider "$DEPS_CANDIDATES_FILE"
grep -Fxq unit-pre "$DEPS_CANDIDATES_FILE"
write_offline_installer
! grep -q '^unit-' "$BUNDLE_ROOT/root-packages.txt"
write_apt_repo_index
validate_offline_dependencies

rm "$APT_DEBS_DIR/unit-provider_2_amd64.deb"
make_deb unit-provider 1
write_apt_repo_index
if validate_offline_dependencies; then
  echo 'An incompatible alternative version was accepted' >&2; exit 1
fi
rm "$APT_DEBS_DIR/unit-provider_1_amd64.deb"
make_deb unit-provider 2
rm "$APT_DEBS_DIR/unit-pre_1_amd64.deb"
write_apt_repo_index
if validate_offline_dependencies; then
  echo 'Missing Pre-Depends was accepted' >&2; exit 1
fi
# A package installed on the builder must not mask a missing offline dependency.
make_deb "$base" 1.0 bash
write_apt_repo_index
if validate_offline_dependencies; then
  echo 'Host-installed bash masked a missing bundled dependency' >&2; exit 1
fi
echo 'Offline alternative/version/Pre-Depends/empty-status tests passed.'
