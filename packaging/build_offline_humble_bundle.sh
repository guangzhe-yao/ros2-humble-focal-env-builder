#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$HOME/ros2_humble_unified/package_out/artifacts}"
OUT_DIR="${OUT_DIR:-$ARTIFACT_DIR/offline}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$(date +%Y%m%d%H%M)}"
PKG_ARCH="${PKG_ARCH:-$(dpkg --print-architecture)}"
BUNDLE_NAME="${BUNDLE_NAME:-ros2-humble-focal-offline-bundle_${BUNDLE_VERSION}_${PKG_ARCH}}"
INCLUDE_DEV_DEPS="${INCLUDE_DEV_DEPS:-0}"
APT_INCLUDE_RECOMMENDS="${APT_INCLUDE_RECOMMENDS:-0}"
APT_DOWNLOAD_TIMEOUT="${APT_DOWNLOAD_TIMEOUT:-300}"
APT_DOWNLOAD_RETRIES="${APT_DOWNLOAD_RETRIES:-3}"
FAIL_ON_MISSING_APT_DEBS="${FAIL_ON_MISSING_APT_DEBS:-0}"

BUNDLE_ROOT="$OUT_DIR/$BUNDLE_NAME"
APT_DEBS_DIR="$BUNDLE_ROOT/apt_debs"
BUNDLE_ARTIFACT_DIR="$BUNDLE_ROOT/artifacts"
DEPS_ROOT_FILE="$BUNDLE_ROOT/apt-root-deps.txt"
DEPS_CLOSURE_FILE="$BUNDLE_ROOT/apt-closure-deps.txt"
MISSING_DEPS_FILE="$BUNDLE_ROOT/apt-missing-deps.txt"
APT_DOWNLOAD_ERRORS_FILE="$BUNDLE_ROOT/apt-download-errors.log"
VIRTUAL_DEPS_FILE="$BUNDLE_ROOT/apt-virtual-deps.txt"

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
  : > "$APT_DOWNLOAD_ERRORS_FILE"
  : > "$VIRTUAL_DEPS_FILE"
  pushd "$APT_DEBS_DIR" >/dev/null

  local attempt candidate pkg
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}' || true)"
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
      printf '%s\n' "$pkg" >> "$MISSING_DEPS_FILE"
      continue
    fi
    log "Downloading apt package: $pkg"
    for attempt in $(seq 1 "$APT_DOWNLOAD_RETRIES"); do
      if timeout "$APT_DOWNLOAD_TIMEOUT" apt-get download "$pkg" >>"$APT_DOWNLOAD_ERRORS_FILE" 2>&1; then
        break
      fi
      if [ "$attempt" = "$APT_DOWNLOAD_RETRIES" ]; then
        printf '%s\n' "$pkg" >> "$MISSING_DEPS_FILE"
      else
        sleep 2
      fi
    done
    if compgen -G "${pkg}_*.deb" >/dev/null; then
      :
    elif grep -Fxq "$pkg" "$MISSING_DEPS_FILE"; then
      :
    else
      printf '%s\n' "$pkg" >> "$MISSING_DEPS_FILE"
    fi
  done < "$DEPS_CLOSURE_FILE"

  if [ -s "$MISSING_DEPS_FILE" ]; then
    local filtered_missing
    filtered_missing="$(mktemp)"
    sort -u "$MISSING_DEPS_FILE" | while IFS= read -r pkg; do
      case "$pkg" in
        awk|debconf-2.0|fonts-freefont|libblas.so.3|liblapack.so.3|python3:any|python3.8:any|qtbase-abi-*)
          printf '%s\n' "$pkg" >> "$VIRTUAL_DEPS_FILE"
          continue
          ;;
      esac
      local lookup_pkg="$pkg"
      lookup_pkg="${lookup_pkg%:any}"
      if find . -maxdepth 1 -name "${lookup_pkg}_*.deb" | grep -q .; then
        continue
      fi
      printf '%s\n' "$pkg" >> "$filtered_missing"
    done
    mv "$filtered_missing" "$MISSING_DEPS_FILE"
  fi

  popd >/dev/null
  log "Downloaded $(find "$APT_DEBS_DIR" -maxdepth 1 -name '*.deb' | wc -l) apt debs"
  if [ -s "$VIRTUAL_DEPS_FILE" ]; then
    echo "Info: some dependency names are virtual or ABI aliases and are expected to be satisfied by downloaded provider packages:" >&2
    sed 's/^/  /' "$VIRTUAL_DEPS_FILE" >&2
  fi
  if [ -s "$MISSING_DEPS_FILE" ]; then
    echo "Warning: some dependency names are virtual or unavailable and were not downloaded:" >&2
    sed 's/^/  /' "$MISSING_DEPS_FILE" >&2
    if [ "$FAIL_ON_MISSING_APT_DEBS" = "1" ]; then
      echo "FAIL_ON_MISSING_APT_DEBS=1: refusing to create an incomplete offline bundle." >&2
      exit 1
    fi
  fi
}

write_apt_repo_index() {
  log "Writing local apt repository index"
  pushd "$APT_DEBS_DIR" >/dev/null
  : > Packages

  local deb
  for deb in ./*.deb; do
    [ -f "$deb" ] || continue
    dpkg-deb -f "$deb" >> Packages
    {
      printf 'Filename: %s\n' "$deb"
      printf 'Size: %s\n' "$(stat -c '%s' "$deb")"
      printf 'MD5sum: %s\n' "$(md5sum "$deb" | awk '{print $1}')"
      printf 'SHA256: %s\n' "$(sha256sum "$deb" | awk '{print $1}')"
      printf '\n'
    } >> Packages
  done
  gzip -kf Packages
  popd >/dev/null
}

write_offline_installer() {
  log "Writing offline installer"
  cat > "$BUNDLE_ROOT/install_offline_humble_bundle.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_DEBS_DIR="$SCRIPT_DIR/apt_debs"
ARTIFACT_DIR="$SCRIPT_DIR/artifacts"
APT_ROOT_DEPS="$SCRIPT_DIR/apt-root-deps.txt"

repair_broken_apt_if_needed() {
  local check_log
  check_log="$(mktemp)"
  if apt-get check >"$check_log" 2>&1; then
    rm -f "$check_log"
    return 0
  fi

  echo "The target machine has broken apt dependencies before ROS 2 installation." >&2
  sed 's/^/  /' "$check_log" >&2
  rm -f "$check_log"

  if [ "${ALLOW_ONLINE_APT_REPAIR:-0}" = "1" ]; then
    echo "ALLOW_ONLINE_APT_REPAIR=1: repairing system apt state with the configured online apt sources."
    apt-get update
    env DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y
    apt-get check
    return 0
  fi

  cat >&2 <<REPAIREOF

Fix the base OS package state first, then rerun this offline installer:
  sudo apt update
  sudo apt --fix-broken install -y
  sudo ./install_offline_humble_bundle.sh

If this machine is allowed to use online apt sources during repair, run:
  ALLOW_ONLINE_APT_REPAIR=1 sudo -E ./install_offline_humble_bundle.sh

REPAIREOF
  exit 1
}

remove_existing_ros2_humble() {
  local installed_packages=()
  mapfile -t installed_packages < <(
    dpkg-query -W -f='${binary:Package}\n' 'ros-humble-*' ros2-humble-focal-desktop-source 2>/dev/null | sort -u
  )

  if [ "${#installed_packages[@]}" -gt 0 ]; then
    apt-get remove -y "${installed_packages[@]}" || true
  else
    echo "No existing ros-humble-* marker packages or main Humble bundle package found."
  fi
  rm -rf /opt/ros/humble
}

install_bundled_apt_dependencies() {
  if [ ! -f "$APT_DEBS_DIR/Packages" ] && [ ! -f "$APT_DEBS_DIR/Packages.gz" ]; then
    echo "Missing local apt index under $APT_DEBS_DIR" >&2
    echo "This offline bundle is incomplete. Regenerate it with the current packaging scripts." >&2
    exit 1
  fi
  if [ ! -f "$APT_ROOT_DEPS" ]; then
    echo "Missing $APT_ROOT_DEPS" >&2
    exit 1
  fi

  local apt_tmp source_list source_parts lists_dir
  apt_tmp="$(mktemp -d)"
  source_list="$apt_tmp/sources.list"
  source_parts="$apt_tmp/sourceparts"
  lists_dir="$apt_tmp/lists"
  mkdir -p "$source_parts" "$lists_dir/partial"
  printf 'deb [trusted=yes] file:%s ./\n' "$APT_DEBS_DIR" > "$source_list"

  local apt_opts=(
    -o "Dir::Etc::sourcelist=$source_list"
    -o "Dir::Etc::sourceparts=$source_parts"
    -o "Dir::State::Lists=$lists_dir"
    -o "APT::Get::List-Cleanup=0"
    -o "Acquire::Languages=none"
  )

  echo "Installing bundled apt dependencies from local repository: $APT_DEBS_DIR"
  apt-get "${apt_opts[@]}" update
  xargs -r -a "$APT_ROOT_DEPS" env DEBIAN_FRONTEND=noninteractive \
    apt-get "${apt_opts[@]}" install -y --no-install-recommends
  rm -rf "$apt_tmp"
}

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
  echo "FORCE_REINSTALL=1 is deprecated for this offline installer; use REINSTALL_EXISTING=1/0. Treating as REINSTALL_EXISTING=1."
  export REINSTALL_EXISTING=1
fi

if [ "${REINSTALL_EXISTING:-1}" = "1" ]; then
  echo "Removing any existing ROS 2 Humble bundle before offline install."
  remove_existing_ros2_humble
fi

repair_broken_apt_if_needed

if compgen -G "$APT_DEBS_DIR/*.deb" >/dev/null; then
  install_bundled_apt_dependencies
else
  echo "Warning: no apt debs found under $APT_DEBS_DIR" >&2
fi

cd "$ARTIFACT_DIR"
FORCE_REINSTALL="${REINSTALL_EXISTING:-1}" \
  INSTALL_APT_DEPS=0 \
  RUN_ROSDEP_UPDATE=0 \
  INSTALL_OVERLAY_TOOLS="${INSTALL_OVERLAY_TOOLS:-0}" \
  ./install_ros2_humble.sh

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
sudo ./install_offline_humble_bundle.sh
\`\`\`

离线安装器默认会先清理旧的 \`/opt/ros/humble\`、\`ros-humble-*\` marker
和主 bundle 包，再安装当前离线包。若只想在发现旧环境时失败而不是覆盖：

\`\`\`bash
REINSTALL_EXISTING=0 sudo -E ./install_offline_humble_bundle.sh
\`\`\`

## 内容

- \`artifacts/\`: 已构建好的 ROS 2 Humble 主 deb、marker deb、CycloneDDS 配置和验证脚本。
- \`apt_debs/\`: 安装器需要的 Ubuntu apt 依赖 deb 包。
- \`apt-root-deps.txt\`: artifacts 声明的直接依赖。
- \`apt-closure-deps.txt\`: 递归解析出的 apt 依赖集合。
- \`apt-virtual-deps.txt\`: apt 输出的虚拟包名或 ABI 别名，已由实际 provider 包满足。
- \`apt-missing-deps.txt\`: 未能下载的虚拟包或网络失败包；如果为空，离线依赖更完整。

目标 Pico 不需要 GitHub，也不需要源码编译。
EOF
}

make_tarball() {
  log "Creating tarball"
  local tarball="$OUT_DIR/$BUNDLE_NAME.tar.gz"
  tar -C "$OUT_DIR" -czf "$tarball" "$BUNDLE_NAME"
  sha256sum "$tarball" > "$tarball.sha256"
  ln -sfn "$(basename "$tarball")" "$OUT_DIR/ros2-humble-focal-offline-bundle_latest_${PKG_ARCH}.tar.gz"
  ln -sfn "$(basename "$tarball").sha256" "$OUT_DIR/ros2-humble-focal-offline-bundle_latest_${PKG_ARCH}.tar.gz.sha256"
  log "Offline bundle created: $tarball"
  log "SHA256: $tarball.sha256"
}

main() {
  require_focal_amd64
  require_artifacts
  prepare_bundle_root
  collect_root_deps
  resolve_apt_closure
  download_apt_debs
  write_apt_repo_index
  write_offline_installer
  write_readme
  make_tarball
}

main "$@"
