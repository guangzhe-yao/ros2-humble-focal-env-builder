#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
export OUT_DIR="$temp/out" PROFILE="$temp/profile.repos" SOURCE_LOCK="$temp/actual.repos"
mkdir -p "$OUT_DIR/artifacts"
printf 'configured profile\n' > "$PROFILE"
printf 'stale provenance\n' > "$OUT_DIR/artifacts/source-lock.repos"
source "$REPO/builder/package/repackage_existing_humble_artifacts.sh"
copy_artifact_metadata
[[ ! -e "$OUT_DIR/artifacts/source-lock.repos" ]]
cmp "$PROFILE" "$OUT_DIR/artifacts/third_party.repos"
printf 'actual source lock\n' > "$SOURCE_LOCK"
copy_artifact_metadata
cmp "$SOURCE_LOCK" "$OUT_DIR/artifacts/source-lock.repos"
echo 'Source metadata truthfulness test passed.'
