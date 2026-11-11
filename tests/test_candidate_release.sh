#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/repo/builder/package" "$temp/source" "$temp/release"
touch "$temp/source/setup.bash"
cp "$REPO/builder/package_installed_pico.sh" "$temp/repo/builder/"
cp "$REPO/builder/package/build_self_extracting.py" "$temp/repo/builder/package/"
# Replace the expensive native build with a candidate-producing fixture.
cat > "$temp/repo/builder/package/repackage_existing_humble_artifacts.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p "$OFFLINE_OUT_DIR"
mkdir -p "$OFFLINE_OUT_DIR/payload"
printf '#!/bin/bash\necho candidate\n' > "$OFFLINE_OUT_DIR/payload/install.sh"
tar -czf "$OFFLINE_OUT_DIR/$BUNDLE_NAME.tar.gz" -C "$OFFLINE_OUT_DIR" payload
(cd "$OFFLINE_OUT_DIR" && sha256sum "$BUNDLE_NAME.tar.gz" > "$BUNDLE_NAME.tar.gz.sha256")
FIXTURE
chmod +x "$temp/repo/builder/package/repackage_existing_humble_artifacts.sh"
export SOURCE_PREFIX="$temp/source" OUT_DIR="$temp/out" RELEASE_DIR="$temp/release"
export OFFLINE_OUT_DIR="$temp/custom-offline" BUNDLE_VERSION=test1
latest="$RELEASE_DIR/ros2-humble-focal-offline-bundle_latest_amd64.tar.gz"
ln -s previously-reviewed.tar.gz "$latest"
entry="$temp/repo/builder/package_installed_pico.sh"
bash "$entry"
bundle=ros2-humble-focal-offline-bundle_test1_amd64.run
[[ -f "$RELEASE_DIR/$bundle" ]]
[[ "$(readlink "$latest")" == previously-reviewed.tar.gz ]]
(cd "$RELEASE_DIR" && sha256sum -c "$bundle.sha256")
original="$(sha256sum "$RELEASE_DIR/$bundle")"
bash "$RELEASE_DIR/$bundle" | grep -Fxq candidate
if bash "$entry"; then
  echo 'Existing candidate was overwritten' >&2; exit 1
fi
[[ "$(sha256sum "$RELEASE_DIR/$bundle")" == "$original" ]]
if BUNDLE_VERSION=../escape bash "$entry"; then
  echo 'Invalid candidate version was accepted' >&2; exit 1
fi
echo 'Candidate publishing preserves latest and existing versions.'
