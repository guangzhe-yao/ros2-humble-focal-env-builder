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
ENABLE_OSRF_GAZEBO_SOURCE="${ENABLE_OSRF_GAZEBO_SOURCE:-1}"
OSRF_GAZEBO_APT_SOURCE="${OSRF_GAZEBO_APT_SOURCE:-deb [trusted=yes] http://packages.osrfoundation.org/gazebo/ubuntu-stable focal main}"
APT_EXCLUDED_PACKAGES_REGEX="${APT_EXCLUDED_PACKAGES_REGEX:-^(python3-rosdep|python3-rosdep2)$}"
EXTRA_APT_ROOT_DEPS_FILE="${EXTRA_APT_ROOT_DEPS_FILE:-}"
EXTRA_APT_DEBS_DIR="${EXTRA_APT_DEBS_DIR:-}"

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

emit_extra_root_deps_files() {
  if [ -z "$EXTRA_APT_ROOT_DEPS_FILE" ]; then
    return 0
  fi

  local extra_file
  local -a extra_dep_files=()
  IFS=':' read -r -a extra_dep_files <<< "$EXTRA_APT_ROOT_DEPS_FILE"
  for extra_file in "${extra_dep_files[@]}"; do
    [ -z "$extra_file" ] && continue
    if [ ! -f "$extra_file" ]; then
      echo "EXTRA_APT_ROOT_DEPS_FILE entry does not exist: $extra_file" >&2
      exit 1
    fi
    sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$extra_file"
  done
}

emit_deb_dependency_names() {
  local deb="$1"
  local field deps

  for field in Pre-Depends Depends; do
    deps="$(dpkg-deb -f "$deb" "$field" 2>/dev/null || true)"
    printf '%s\n' "$deps" \
      | tr ',' '\n' \
      | awk '
          {
            sub(/\|.*/, "", $0)
            sub(/\(.*/, "", $0)
            gsub(/^[ \t]+|[ \t]+$/, "", $0)
            split($0, words, /[ \t]+/)
            if (words[1] != "") print words[1]
          }
        '
  done
}

emit_artifact_deb_root_deps() {
  local deb
  while IFS= read -r -d '' deb; do
    emit_deb_dependency_names "$deb"
  done < <(
    find "$ARTIFACT_DIR" -maxdepth 1 -type f \
      -name "ros2-humble-focal-desktop-source_*_${PKG_ARCH}.deb" -print0
  )
}

emit_extra_deb_root_deps() {
  if [ -z "$EXTRA_APT_DEBS_DIR" ]; then
    return 0
  fi

  local extra_dir deb
  local -a extra_deb_dirs=()
  IFS=':' read -r -a extra_deb_dirs <<< "$EXTRA_APT_DEBS_DIR"
  for extra_dir in "${extra_deb_dirs[@]}"; do
    [ -z "$extra_dir" ] && continue
    if [ ! -d "$extra_dir" ]; then
      echo "EXTRA_APT_DEBS_DIR entry does not exist: $extra_dir" >&2
      exit 1
    fi
    while IFS= read -r -d '' deb; do
      dpkg-deb -f "$deb" Package 2>/dev/null || true
      emit_deb_dependency_names "$deb"
    done < <(find "$extra_dir" -maxdepth 1 -type f -name '*.deb' -print0)
  done
}

collect_root_deps() {
  log "Collecting root apt dependency package names"
  {
    sed '/^$/d' "$ARTIFACT_DIR/runtime-deps.txt"
    # The deb control file is authoritative when reusing older artifacts.
    emit_artifact_deb_root_deps
    if [ "$INCLUDE_DEV_DEPS" = "1" ] && [ -f "$ARTIFACT_DIR/dev-deps.txt" ]; then
      sed '/^$/d' "$ARTIFACT_DIR/dev-deps.txt"
    fi
    emit_extra_root_deps_files
    emit_extra_deb_root_deps
  } | awk -v re="$APT_EXCLUDED_PACKAGES_REGEX" 'NF && (re == "" || $0 !~ re)' \
    | sort -u > "$DEPS_ROOT_FILE"
}

copy_extra_apt_debs() {
  if [ -z "$EXTRA_APT_DEBS_DIR" ]; then
    return 0
  fi

  local extra_dir
  local -a extra_deb_dirs=()
  IFS=':' read -r -a extra_deb_dirs <<< "$EXTRA_APT_DEBS_DIR"
  for extra_dir in "${extra_deb_dirs[@]}"; do
    [ -z "$extra_dir" ] && continue
    if [ ! -d "$extra_dir" ]; then
      echo "EXTRA_APT_DEBS_DIR entry does not exist: $extra_dir" >&2
      exit 1
    fi
    log "Copying extra local debs from $extra_dir"
    find "$extra_dir" -maxdepth 1 -type f -name '*.deb' -print0 \
      | xargs -0 -r cp -t "$APT_DEBS_DIR"
  done
}

resolve_apt_closure() {
  log "Resolving recursive apt dependency closure"
  local depends_flags=(
    --no-suggests
    --no-conflicts
    --no-breaks
    --no-replaces
    --no-enhances
  )
  if [ "$APT_INCLUDE_RECOMMENDS" != "1" ]; then
    depends_flags+=(--no-recommends)
  fi

  local dep_line_re='^[[:space:]]*\|?(PreDepends|Depends):[[:space:]]'
  if [ "$APT_INCLUDE_RECOMMENDS" = "1" ]; then
    dep_line_re='^[[:space:]]*\|?(PreDepends|Depends|Recommends):[[:space:]]'
  fi

  local -a queue=()
  local pkg dep candidate
  declare -A seen=()
  mapfile -t queue < "$DEPS_ROOT_FILE"
  : > "$DEPS_CLOSURE_FILE"

  while [ "${#queue[@]}" -gt 0 ]; do
    pkg="${queue[0]}"
    queue=("${queue[@]:1}")
    [ -z "$pkg" ] && continue
    if [ -n "$APT_EXCLUDED_PACKAGES_REGEX" ] && [[ "$pkg" =~ $APT_EXCLUDED_PACKAGES_REGEX ]]; then
      continue
    fi
    if [ "${seen[$pkg]+set}" = "set" ]; then
      continue
    fi
    seen["$pkg"]=1
    printf '%s\n' "$pkg" >> "$DEPS_CLOSURE_FILE"

    candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}' || true)"
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
      continue
    fi

    while IFS= read -r dep; do
      dep="${dep//[<>]/}"
      dep="${dep//,/}"
      [ -z "$dep" ] && continue
      if [ -n "$APT_EXCLUDED_PACKAGES_REGEX" ] && [[ "$dep" =~ $APT_EXCLUDED_PACKAGES_REGEX ]]; then
        continue
      fi
      if [ "${seen[$dep]+set}" != "set" ]; then
        queue+=("$dep")
      fi
    done < <(
      apt-cache depends "${depends_flags[@]}" "$pkg" \
        | awk -v re="$dep_line_re" '$0 ~ re {print $2}' \
        | sed -e 's/[<>=]//g' -e '/^$/d'
    )
  done

  sort -u -o "$DEPS_CLOSURE_FILE" "$DEPS_CLOSURE_FILE"
}

download_apt_debs() {
  log "Downloading apt debs into $APT_DEBS_DIR"
  : > "$MISSING_DEPS_FILE"
  : > "$APT_DOWNLOAD_ERRORS_FILE"
  : > "$VIRTUAL_DEPS_FILE"
  copy_extra_apt_debs
  pushd "$APT_DEBS_DIR" >/dev/null

  local attempt candidate pkg
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}' || true)"
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
      if [ "$pkg" = "libignition-math6" ] && [ "$ENABLE_OSRF_GAZEBO_SOURCE" = "1" ]; then
        if download_osrf_gazebo_deb "$pkg"; then
          continue
        fi
      fi
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
        awk|dbus-session-bus|debconf-2.0|default-dbus-session-bus|fonts-freefont|gsettings-backend|libblas.so.3|liblapack.so.3|libopencl-1.1-1|libopencl-1.2-1|libopencl1|python3:any|python3.8:any|qtbase-abi-*|qtdeclarative-abi-*)
          printf '%s\n' "$pkg" >> "$VIRTUAL_DEPS_FILE"
          continue
          ;;
      esac
      local lookup_pkg="$pkg"
      lookup_pkg="${lookup_pkg%:any}"
      lookup_pkg="${lookup_pkg%:amd64}"
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

download_osrf_gazebo_deb() {
  local pkg="$1"
  local apt_tmp source_list source_parts lists_dir
  apt_tmp="$(mktemp -d)"
  source_list="$apt_tmp/sources.list"
  source_parts="$apt_tmp/sourceparts"
  lists_dir="$apt_tmp/lists"
  mkdir -p "$source_parts" "$lists_dir/partial"
  printf '%s\n' "$OSRF_GAZEBO_APT_SOURCE" > "$source_list"

  local apt_opts=(
    -o "Dir::Etc::sourcelist=$source_list"
    -o "Dir::Etc::sourceparts=$source_parts"
    -o "Dir::State::Lists=$lists_dir"
    -o "APT::Get::List-Cleanup=0"
    -o "Acquire::Languages=none"
  )

  log "Downloading apt package from OSRF Gazebo source: $pkg"
  if apt-get "${apt_opts[@]}" update >>"$APT_DOWNLOAD_ERRORS_FILE" 2>&1 \
      && apt-get "${apt_opts[@]}" download "$pkg" >>"$APT_DOWNLOAD_ERRORS_FILE" 2>&1; then
    rm -rf "$apt_tmp"
    return 0
  fi
  rm -rf "$apt_tmp"
  return 1
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
  local apt_install_cmd=(
    apt-get "${apt_opts[@]}" install
    -y
    --no-install-recommends
    --no-upgrade
  )
  local apt_sim_log
  apt_sim_log="$(mktemp)"

  echo "Installing bundled apt dependencies from local repository: $APT_DEBS_DIR"
  apt-get "${apt_opts[@]}" update
  if ! xargs -r -a "$APT_ROOT_DEPS" env DEBIAN_FRONTEND=noninteractive \
      "${apt_install_cmd[@]}" -s >"$apt_sim_log" 2>&1; then
    echo "Unable to resolve bundled apt dependencies safely." >&2
    sed 's/^/  /' "$apt_sim_log" >&2
    rm -f "$apt_sim_log"
    exit 1
  fi
  if grep -Eq '^(The following packages will be REMOVED:|WARNING: The following essential packages will be removed)' "$apt_sim_log"; then
    echo "Refusing to install bundled apt dependencies because apt planned package removals." >&2
    echo "This usually means the target OS package baseline is inconsistent with the bundle." >&2
    sed 's/^/  /' "$apt_sim_log" >&2
    rm -f "$apt_sim_log"
    exit 1
  fi
  rm -f "$apt_sim_log"

  xargs -r -a "$APT_ROOT_DEPS" env DEBIAN_FRONTEND=noninteractive \
    "${apt_install_cmd[@]}"
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

运行版离线包不默认安装 \`python3-rosdep\` / \`python3-rosdep2\`，避免在保留
ROS 1/Noetic 的机器上触发 apt 删除 \`ros-noetic-*\` 或业务包。需要在目标机上
编译 overlay 时，再按该机器的 ROS 1/ROS 2 共存策略单独处理 rosdep。

目标 Pico 不需要 GitHub，也不需要源码编译。
EOF
}

make_tarball() {
  log "Creating tarball"
  local tarball="$OUT_DIR/$BUNDLE_NAME.tar.gz"
  tar -C "$OUT_DIR" -czf "$tarball" "$BUNDLE_NAME"
  (cd "$OUT_DIR" && sha256sum "$(basename "$tarball")" > "$(basename "$tarball").sha256")
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
