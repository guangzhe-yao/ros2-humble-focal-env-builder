#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$HOME/ros2_humble_unified/package_out/artifacts}"
OUT_DIR="${OUT_DIR:-$ARTIFACT_DIR/offline}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$(date +%Y%m%d%H%M)}"
PKG_ARCH="${PKG_ARCH:-$(dpkg --print-architecture)}"
BUNDLE_NAME="${BUNDLE_NAME:-ros2-humble-focal-offline-bundle_${BUNDLE_VERSION}_${PKG_ARCH}}"
INCLUDE_DEV_DEPS="${INCLUDE_DEV_DEPS:-1}"
APT_INCLUDE_RECOMMENDS="${APT_INCLUDE_RECOMMENDS:-0}"

BUNDLE_ROOT="$OUT_DIR/$BUNDLE_NAME"
APT_DEBS_DIR="$BUNDLE_ROOT/apt_debs"
BUNDLE_ARTIFACT_DIR="$BUNDLE_ROOT/artifacts"
DEPS_ROOT_FILE="$BUNDLE_ROOT/apt-root-deps.txt"
DEPS_CLOSURE_FILE="$BUNDLE_ROOT/apt-closure-deps.txt"
MISSING_DEPS_FILE="$BUNDLE_ROOT/apt-missing-deps.txt"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

require_focal_amd64() {
  . /etc/os-release
  if [ "${VERSION_CODENAME:-}" != "focal" ]; then
    echo "This offline bundle must be built on Ubuntu 20.04 focal; got ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo "This offline bundle currently supports amd64 only; got $(dpkg --print-architecture)" >&2
    exit 1
  fi
}

require_artifacts() {
  local missing=()
  [ -x "$ARTIFACT_DIR/install_ros2_humble.sh" ] || missing+=("$ARTIFACT_DIR/install_ros2_humble.sh")
  compgen -G "$ARTIFACT_DIR/ros2-humble-focal-desktop-source_*_${PKG_ARCH}.deb" >/dev/null || missing+=("main ros2-humble deb")
  compgen -G "$ARTIFACT_DIR/ros-humble-package-markers_*_${PKG_ARCH}.tar.gz" >/dev/null || missing+=("marker tar")
  [ -f "$ARTIFACT_DIR/runtime-deps.txt" ] || missing+=("$ARTIFACT_DIR/runtime-deps.txt")

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing generated artifacts:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi

  if ! grep -Fq 'INSTALL_APT_DEPS' "$ARTIFACT_DIR/install_ros2_humble.sh"; then
    echo "The installer under $ARTIFACT_DIR is from an older artifact set and does not support offline mode." >&2
    echo "Regenerate artifacts with the current repository before building an offline bundle." >&2
    exit 1
  fi
}

prepare_bundle_root() {
  log "Preparing offline bundle root: $BUNDLE_ROOT"
  rm -rf "$BUNDLE_ROOT"
  mkdir -p "$APT_DEBS_DIR" "$BUNDLE_ARTIFACT_DIR"
  rsync -a --delete \
    --exclude 'offline/' \
    "$ARTIFACT_DIR/" "$BUNDLE_ARTIFACT_DIR/"
}

collect_root_deps() {
  log "Collecting root apt dependency package names"
  {
    sed '/^$/d' "$ARTIFACT_DIR/runtime-deps.txt"
    if [ "$INCLUDE_DEV_DEPS" = "1" ] && [ -f "$ARTIFACT_DIR/dev-deps.txt" ]; then
      sed '/^$/d' "$ARTIFACT_DIR/dev-deps.txt"
    fi
  } | sort -u > "$DEPS_ROOT_FILE"
}

resolve_apt_closure() {
  log "Resolving recursive apt dependency closure"
  local depends_flags=(
    --recurse
    --no-suggests
    --no-conflicts
    --no-breaks
    --no-replaces
    --no-enhances
  )
  if [ "$APT_INCLUDE_RECOMMENDS" != "1" ]; then
    depends_flags+=(--no-recommends)
  fi

  mapfile -t root_deps < "$DEPS_ROOT_FILE"
  apt-cache depends "${depends_flags[@]}" "${root_deps[@]}" \
    | awk '
        /^[[:alnum:]][[:alnum:].+:-]+$/ {print $1}
        /^[[:space:]]*(PreDepends|Depends|Recommends):[[:space:]]/ {print $2}
      ' \
    | sed -e 's/[<>=]//g' \
    | sed '/^$/d' \
    | sort -u > "$DEPS_CLOSURE_FILE"
}

download_apt_debs() {
  log "Downloading apt debs into $APT_DEBS_DIR"
  : > "$MISSING_DEPS_FILE"
  pushd "$APT_DEBS_DIR" >/dev/null

  local pkg
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    if ! apt-cache show "$pkg" >/dev/null 2>&1; then
      printf '%s\n' "$pkg" >> "$MISSING_DEPS_FILE"
      continue
    fi
    apt-get download "$pkg" >/dev/null
  done < "$DEPS_CLOSURE_FILE"

  popd >/dev/null
  log "Downloaded $(find "$APT_DEBS_DIR" -maxdepth 1 -name '*.deb' | wc -l) apt debs"
  if [ -s "$MISSING_DEPS_FILE" ]; then
    echo "Warning: some dependency names are virtual or unavailable and were not downloaded:" >&2
    sed 's/^/  /' "$MISSING_DEPS_FILE" >&2
  fi
}

write_offline_installer() {
  log "Writing offline installer"
  cat > "$BUNDLE_ROOT/install_offline_humble_bundle.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_DEBS_DIR="$SCRIPT_DIR/apt_debs"
ARTIFACT_DIR="$SCRIPT_DIR/artifacts"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo: sudo $0" >&2
  exit 1
fi

. /etc/os-release
if [ "${VERSION_CODENAME:-}" != "focal" ]; then
  echo "This offline bundle is for Ubuntu 20.04 focal only; got ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi
if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "This offline bundle is for amd64 only; got $(dpkg --print-architecture)" >&2
  exit 1
fi

if [ "${FORCE_REINSTALL:-0}" = "1" ]; then
  apt remove -y 'ros-humble-*' ros2-humble-focal-desktop-source || true
  rm -rf /opt/ros/humble
fi

if compgen -G "$APT_DEBS_DIR/*.deb" >/dev/null; then
  echo "Installing bundled apt dependencies from $APT_DEBS_DIR"
  mkdir -p /var/cache/apt/archives
  cp -n "$APT_DEBS_DIR"/*.deb /var/cache/apt/archives/ || true
  dpkg -i "$APT_DEBS_DIR"/*.deb || apt-get --no-download -f install -y
else
  echo "Warning: no apt debs found under $APT_DEBS_DIR" >&2
fi

cd "$ARTIFACT_DIR"
INSTALL_APT_DEPS=0 RUN_ROSDEP_UPDATE=0 ./install_ros2_humble.sh

cat <<MSG

Offline ROS 2 Humble install finished.

Use:
  source /etc/ros/source_ros2_humble_clean.bash
  ./artifacts/verify_installed_humble_env.sh

MSG
EOF
  chmod 0755 "$BUNDLE_ROOT/install_offline_humble_bundle.sh"
}

write_readme() {
  cat > "$BUNDLE_ROOT/README_OFFLINE.zh-CN.md" <<EOF
# ROS 2 Humble Focal 离线安装包

这个目录由 \`packaging/build_offline_humble_bundle.sh\` 生成，用于同型号
Ubuntu 20.04 amd64 Pico 离线安装 ROS 2 Humble 前置环境。

## 安装

\`\`\`bash
sudo ./install_offline_humble_bundle.sh
source /etc/ros/source_ros2_humble_clean.bash
./artifacts/verify_installed_humble_env.sh
\`\`\`

如果目标机器已有旧环境，并确认要覆盖：

\`\`\`bash
FORCE_REINSTALL=1 sudo -E ./install_offline_humble_bundle.sh
\`\`\`

## 内容

- \`artifacts/\`: 已构建好的 ROS 2 Humble 主 deb、marker deb、CycloneDDS 配置和验证脚本。
- \`apt_debs/\`: 安装器需要的 Ubuntu apt 依赖 deb 包。
- \`apt-root-deps.txt\`: artifacts 声明的直接依赖。
- \`apt-closure-deps.txt\`: 递归解析出的 apt 依赖集合。

目标 Pico 不需要 GitHub，也不需要源码编译。
EOF
}

make_tarball() {
  log "Creating tarball"
  tar -C "$OUT_DIR" -czf "$OUT_DIR/$BUNDLE_NAME.tar.gz" "$BUNDLE_NAME"
  log "Offline bundle created: $OUT_DIR/$BUNDLE_NAME.tar.gz"
}

main() {
  require_focal_amd64
  require_artifacts
  prepare_bundle_root
  collect_root_deps
  resolve_apt_closure
  download_apt_debs
  write_offline_installer
  write_readme
  make_tarball
}

main "$@"
