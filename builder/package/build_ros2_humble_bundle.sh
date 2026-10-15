#!/usr/bin/env bash
set -Eeuo pipefail

SRC_PREFIX="${SRC_PREFIX:-$HOME/ros2_humble/install_deploy}"
OUT_DIR="${OUT_DIR:-$HOME/ros2_humble_deploy}"
PKG_NAME="${PKG_NAME:-ros2-humble-focal-desktop-source}"
PKG_VERSION="${PKG_VERSION:-0.1.0+$(date +%Y%m%d%H%M)}"
PKG_ARCH="${PKG_ARCH:-$(dpkg --print-architecture)}"
MAINTAINER="${MAINTAINER:-nav01 <nav01@localhost>}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/ros/humble}"
BUILD_BASE="${BUILD_BASE:-$HOME/ros2_humble/build_deploy}"
BUILD_LOG="${BUILD_LOG:-$HOME/ros2_humble/colcon_build_humble_deploy.log}"
BUILD_DIR="$OUT_DIR/build"
PKGROOT="$BUILD_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"
STAGED_PREFIX="$PKGROOT$INSTALL_PREFIX"
ARTIFACT_DIR="$OUT_DIR/artifacts"
DEPS_FILE="$BUILD_DIR/runtime-deps.txt"
MANUAL_DEPS_FILE="$BUILD_DIR/manual-runtime-deps.txt"
DEV_DEPS_FILE="$BUILD_DIR/dev-deps.txt"
MARKER_SET_NAME="ros-humble-package-markers_${PKG_VERSION}_${PKG_ARCH}"
MARKER_DIR="$BUILD_DIR/$MARKER_SET_NAME"
MARKER_TAR="$ARTIFACT_DIR/${MARKER_SET_NAME}.tar.gz"
ROSDEP_RULES_FILE="$ARTIFACT_DIR/rosdep-humble-focal-source-build.yaml"
ROSDEP_RULES_BASENAME="$(basename "$ROSDEP_RULES_FILE")"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

require_focal_amd64() {
  . /etc/os-release
  if [ "${VERSION_CODENAME:-}" != "focal" ]; then
    echo "This bundle must be built on Ubuntu focal; got ${VERSION_CODENAME:-unknown}" >&2
    exit 1
  fi
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo "This bundle currently supports amd64 only; got $(dpkg --print-architecture)" >&2
    exit 1
  fi
}

require_packaging_tools() {
  if ! command -v patchelf >/dev/null 2>&1; then
    echo "Missing patchelf. Install it on the packaging machine: sudo apt-get install -y patchelf" >&2
    exit 1
  fi
}

prepare_dirs() {
  log "Preparing package root at $PKGROOT"
  rm -rf "$PKGROOT"
  mkdir -p "$STAGED_PREFIX" "$PKGROOT/DEBIAN" "$ARTIFACT_DIR" "$BUILD_DIR"
  rm -f \
    "$ARTIFACT_DIR/${PKG_NAME}_"*"_${PKG_ARCH}.deb" \
    "$ARTIFACT_DIR/${PKG_NAME}_"*"_${PKG_ARCH}.deb.info" \
    "$ARTIFACT_DIR/${PKG_NAME}_"*"_${PKG_ARCH}.deb.contents" \
    "$ARTIFACT_DIR"/ros-humble-package-markers_*"_${PKG_ARCH}.tar.gz"
}

copy_install_space() {
  log "Copying ROS 2 install space with symlinks expanded"
  rsync -aL --delete \
    --exclude '__pycache__/' \
    --exclude '*.pyc' \
    "$SRC_PREFIX/" "$STAGED_PREFIX/"

  # Business interfaces must be owned by their own DEBs, not the ROS underlay.
  python3 "$(dirname "${BASH_SOURCE[0]}")/prune_business_packages.py" \
    "$STAGED_PREFIX" navi_robot_msgs robot_nodes_py \
    > "$ARTIFACT_DIR/excluded-business-files.txt"

  mkdir -p "$STAGED_PREFIX/share/ros2_humble_source_build"
  cat > "$STAGED_PREFIX/share/ros2_humble_source_build/BUILD_INFO" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Built-At: $(date -Is)
Built-On: $(hostname)
Source-Prefix: $SRC_PREFIX
Install-Prefix: $INSTALL_PREFIX
Ubuntu: $(lsb_release -ds 2>/dev/null || true)
Architecture: $PKG_ARCH
ROS-Build-Summary: $(grep -E '^Summary:' "$BUILD_LOG" 2>/dev/null | tail -n 1 || true)
EOF
}

replace_text_reference() {
  local from="$1"
  local to="$2"
  local matches="$BUILD_DIR/text-rewrite-files.txt"

  if [ "$from" = "$to" ]; then
    return 0
  fi

  grep -RIl --exclude-dir='__pycache__' --exclude='*.pyc' -- "$from" "$STAGED_PREFIX" 2>/dev/null \
    | sort -u > "$matches" || true
  if [ ! -s "$matches" ]; then
    return 0
  fi

  log "Rewriting $(wc -l < "$matches") text references: $from -> $to"
  while IFS= read -r file; do
    FROM="$from" TO="$to" perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$file"
  done < "$matches"
}

rewrite_text_references() {
  log "Rewriting install-space text references for $INSTALL_PREFIX"
  replace_text_reference "$SRC_PREFIX" "$INSTALL_PREFIX"
  replace_text_reference "$HOME/ros2_humble/install_deploy" "$INSTALL_PREFIX"
  replace_text_reference "$BUILD_BASE/rviz_ogre_vendor/ogre_install" "$INSTALL_PREFIX/opt/rviz_ogre_vendor"
  replace_text_reference "$BUILD_BASE/rviz_assimp_vendor/assimp_install" "$INSTALL_PREFIX/opt/rviz_assimp_vendor"
  replace_text_reference "$BUILD_BASE/console_bridge_vendor/console_bridge_vendor_install" "$INSTALL_PREFIX"
  replace_text_reference "$BUILD_BASE/google_benchmark_vendor/google_benchmark_vendor_install" "$INSTALL_PREFIX"
}

normalize_parent_prefix_paths() {
  log "Normalizing ament parent-prefix index"
  local index_dir="$STAGED_PREFIX/share/ament_index/resource_index/parent_prefix_path"
  [ -d "$index_dir" ] || return 0

  local file content entry mapped normalized
  local -A seen=()
  local -a entries=()
  while IFS= read -r -d '' file; do
    content="$(<"$file")"
    normalized=""
    seen=()
    entries=()
    IFS=':' read -r -a entries <<< "$content"
    for entry in "${entries[@]}"; do
      [ -z "$entry" ] && continue
      mapped="$entry"
      case "$entry" in
        /home/*|*/install_deploy|*/install_deploy/*)
          mapped="$INSTALL_PREFIX"
          ;;
      esac
      if [ "${seen[$mapped]+set}" = "set" ]; then
        continue
      fi
      seen["$mapped"]=1
      if [ -z "$normalized" ]; then
        normalized="$mapped"
      else
        normalized="$normalized:$mapped"
      fi
    done
    printf '%s' "$normalized" > "$file"
  done < <(find "$index_dir" -type f -print0)
}

write_single_prefix_setup_scripts() {
  log "Writing single-prefix setup scripts"

  cat > "$STAGED_PREFIX/setup.bash" <<'EOF'
# generated for relocated ROS 2 Humble bundle

_colcon_prefix_chain_bash_source_script() {
  if [ -f "$1" ]; then
    if [ -n "${COLCON_TRACE:-}" ]; then
      echo "# . \"$1\""
    fi
    . "$1"
  else
    echo "not found: \"$1\"" 1>&2
  fi
}

COLCON_CURRENT_PREFIX="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)"
_colcon_prefix_chain_bash_source_script "$COLCON_CURRENT_PREFIX/local_setup.bash"

unset COLCON_CURRENT_PREFIX
unset -f _colcon_prefix_chain_bash_source_script
EOF

  cat > "$STAGED_PREFIX/setup.zsh" <<'EOF'
# generated for relocated ROS 2 Humble bundle

_colcon_prefix_chain_zsh_source_script() {
  if [ -f "$1" ]; then
    if [ -n "${COLCON_TRACE:-}" ]; then
      echo "# . \"$1\""
    fi
    . "$1"
  else
    echo "not found: \"$1\"" 1>&2
  fi
}

COLCON_CURRENT_PREFIX="$(builtin cd -q "$(dirname "${(%):-%N}")" > /dev/null && pwd)"
_colcon_prefix_chain_zsh_source_script "$COLCON_CURRENT_PREFIX/local_setup.zsh"

unset COLCON_CURRENT_PREFIX
unset -f _colcon_prefix_chain_zsh_source_script
EOF

  cat > "$STAGED_PREFIX/setup.sh" <<EOF
# generated for relocated ROS 2 Humble bundle

_colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX="$INSTALL_PREFIX"
if [ ! -z "\${COLCON_CURRENT_PREFIX:-}" ]; then
  _colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX="\$COLCON_CURRENT_PREFIX"
elif [ ! -d "\$_colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX" ]; then
  echo "The install prefix \"\$_colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX\" does not exist." 1>&2
  unset _colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX
  return 1
fi

_colcon_prefix_chain_sh_source_script() {
  if [ -f "\$1" ]; then
    if [ -n "\${COLCON_TRACE:-}" ]; then
      echo "# . \"\$1\""
    fi
    . "\$1"
  else
    echo "not found: \"\$1\"" 1>&2
  fi
}

COLCON_CURRENT_PREFIX="\$_colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX"
_colcon_prefix_chain_sh_source_script "\$COLCON_CURRENT_PREFIX/local_setup.sh"

unset _colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX
unset _colcon_prefix_chain_sh_source_script
unset COLCON_CURRENT_PREFIX
EOF

  cat > "$STAGED_PREFIX/setup.ps1" <<'EOF'
# generated for relocated ROS 2 Humble bundle

$colconCurrentPrefix = Split-Path $MyInvocation.MyCommand.Path
$localSetup = Join-Path $colconCurrentPrefix "local_setup.ps1"
if (Test-Path $localSetup) {
  if ($env:COLCON_TRACE) {
    Write-Output ". `"$localSetup`""
  }
  . $localSetup
} else {
  Write-Error "not found: `"$localSetup`""
}
EOF
}

rewrite_one_rpath() {
  local elf="$1"
  local rpath new_rpath entry mapped suffix
  local -A seen=()
  local -a rpath_entries=()

  rpath="$(patchelf --print-rpath "$elf" 2>/dev/null || true)"
  if [ -z "$rpath" ]; then
    return 0
  fi

  new_rpath=""
  IFS=':' read -r -a rpath_entries <<< "$rpath"
  for entry in "${rpath_entries[@]}"; do
    [ -z "$entry" ] && continue
    mapped="$entry"
    case "$entry" in
      "$BUILD_BASE/rviz_ogre_vendor/ogre_install"*)
        suffix="${entry#"$BUILD_BASE/rviz_ogre_vendor/ogre_install"}"
        mapped="$INSTALL_PREFIX/opt/rviz_ogre_vendor$suffix"
        ;;
      "$BUILD_BASE/rviz_assimp_vendor/assimp_install"*)
        suffix="${entry#"$BUILD_BASE/rviz_assimp_vendor/assimp_install"}"
        mapped="$INSTALL_PREFIX/opt/rviz_assimp_vendor$suffix"
        ;;
      */install_deploy)
        mapped="$INSTALL_PREFIX"
        ;;
      */install_deploy/*)
        suffix="${entry#*/install_deploy}"
        mapped="$INSTALL_PREFIX$suffix"
        ;;
      /home/*)
        # Build-tree RPATH entries must not be shipped to another Pico.
        continue
        ;;
    esac
    if [ "${seen[$mapped]+set}" = "set" ]; then
      continue
    fi
    seen["$mapped"]=1
    if [ -z "$new_rpath" ]; then
      new_rpath="$mapped"
    else
      new_rpath="$new_rpath:$mapped"
    fi
  done

  if [ "$new_rpath" != "$rpath" ]; then
    patchelf --set-rpath "$new_rpath" "$elf"
    printf '%s\n' "$elf" >> "$BUILD_DIR/patched-rpaths.txt"
  fi
}

rewrite_elf_rpaths() {
  log "Rewriting ELF RPATH/RUNPATH entries"
  local elf_list="$BUILD_DIR/elf-files-for-rpath.txt"
  : > "$BUILD_DIR/patched-rpaths.txt"

  find "$STAGED_PREFIX" -type f -print0 \
    | xargs -0 file \
    | awk -F: '/ELF/ {print $1}' \
    | sort -u > "$elf_list"

  while IFS= read -r elf; do
    rewrite_one_rpath "$elf"
  done < "$elf_list"

  log "Patched RPATH/RUNPATH in $(wc -l < "$BUILD_DIR/patched-rpaths.txt") ELF files"
}

validate_relocated_install_space() {
  log "Checking for build-host path references"
  local text_refs="$BUILD_DIR/build-host-text-references.txt"
  local link_refs="$BUILD_DIR/build-host-symlink-references.txt"
  local rpath_refs="$BUILD_DIR/build-host-rpath-references.txt"
  : > "$text_refs"
  : > "$link_refs"
  : > "$rpath_refs"

  grep -RIl --binary-files=without-match \
    --exclude-dir='__pycache__' --exclude='*.pyc' \
    -E '/home/[^/]+/(ros2_humble|ros2-humble|jenkins_workspace)' \
    "$STAGED_PREFIX" 2>/dev/null | sort -u > "$text_refs" || true

  find "$STAGED_PREFIX" -type l -lname '/home/*' -print \
    | sort -u > "$link_refs"

  local elf rpath
  while IFS= read -r elf; do
    rpath="$(patchelf --print-rpath "$elf" 2>/dev/null || true)"
    if [[ "$rpath" == *"/home/"* ]]; then
      printf '%s: %s\n' "$elf" "$rpath" >> "$rpath_refs"
    fi
  done < "$BUILD_DIR/elf-files-for-rpath.txt"

  if [ -s "$text_refs" ] || [ -s "$link_refs" ] || [ -s "$rpath_refs" ]; then
    echo "Build-host paths remain in the relocated install space:" >&2
    sed 's/^/  text: /' "$text_refs" >&2
    sed 's/^/  link: /' "$link_refs" >&2
    sed 's/^/  rpath: /' "$rpath_refs" >&2
    exit 1
  fi
}

relocate_install_space() {
  rewrite_text_references
  normalize_parent_prefix_paths
  write_single_prefix_setup_scripts
  rewrite_elf_rpaths
  validate_relocated_install_space
}

write_manual_deps() {
  cat > "$MANUAL_DEPS_FILE" <<'EOF'
bash
bash-completion
ca-certificates
curl
dbus-user-session
libacl1
libassimp5
libcwiid1
libfreeimage3
libignition-math6
libilmbase24
libopencv-core4.2
libopencv-highgui4.2
libopencv-imgcodecs4.2
libopencv-imgproc4.2
libopencv-videoio4.2
libopenexr24
libpython3.8
libpyside2-py3-5.14
libqt5core5a
libqt5gui5
libqt5opengl5
libqt5svg5
libqt5widgets5
libsdl2-2.0-0
libshiboken2-py3-5.14
libspdlog1
libspnav0
libyaml-cpp0.6
python3
python3-argcomplete
python3-catkin-pkg
python3-empy
python3-importlib-metadata
python3-lark
python3-netifaces
python3-numpy
python3-packaging
python3-pkg-resources
python3-psutil
python3-pygraphviz
python3-yaml
EOF

  cat > "$DEV_DEPS_FILE" <<'EOF'
build-essential
chrony
cmake
git
libasio-dev
libboost-filesystem-dev
libboost-regex-dev
libboost-serialization-dev
libboost-thread-dev
libeigen3-dev
libfmt-dev
libgoogle-glog-dev
libhdf5-dev
libnl-3-dev
libspdlog-dev
libyaml-cpp-dev
libzmq3-dev
pkg-config
python3-colcon-common-extensions
python3-pip
python3-vcstool
python3-venv
sysstat
EOF
}

scan_runtime_deps() {
  log "Scanning ELF runtime dependencies"
  write_manual_deps
  local elf_list="$BUILD_DIR/elf-files.txt"
  local libs_list="$BUILD_DIR/linked-libs.txt"
  local pkgs_list="$BUILD_DIR/linked-packages.txt"

  find "$STAGED_PREFIX" -type f -print0 \
    | xargs -0 file \
    | awk -F: '/ELF/ {print $1}' \
    | sort -u > "$elf_list"

  : > "$libs_list"
  while IFS= read -r elf; do
    LD_LIBRARY_PATH="$(find "$STAGED_PREFIX" -type d \( -name lib -o -path '*/lib/*' \) -print | paste -sd: -)" \
      ldd "$elf" 2>/dev/null \
      | awk '
          /=> \// {print $(NF-1)}
          /^[[:space:]]*\// {print $1}
        ' >> "$libs_list" || true
  done < "$elf_list"

  sort -u "$libs_list" \
    | grep -E '^/(lib|usr/lib|usr/local/lib)/' \
    | while IFS= read -r lib; do
        dpkg-query -S "$lib" 2>/dev/null | sed 's/: .*//' | head -n 1 || true
      done \
    | grep -v '^$' \
    | grep -v '^ros-humble-' \
    | sort -u > "$pkgs_list"

  cat "$MANUAL_DEPS_FILE" "$pkgs_list" \
    | sed '/^$/d' \
    | sort -u > "$DEPS_FILE"

  log "Runtime dependency package count: $(wc -l < "$DEPS_FILE")"
}

write_control_files() {
  log "Writing Debian control files"
  local installed_size
  installed_size="$(du -sk "$PKGROOT" | awk '{print $1}')"
  local depends
  depends="$(awk 'BEGIN{first=1} {if (!first) printf ", "; printf "%s", $0; first=0} END{print ""}' "$DEPS_FILE")"

  cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Section: misc
Priority: optional
Architecture: $PKG_ARCH
Maintainer: $MAINTAINER
Installed-Size: $installed_size
Depends: $depends
Description: Source-built ROS 2 Humble desktop bundle for Ubuntu 20.04 amd64
 This package installs a relocated source-built ROS 2 Humble desktop install
 tree under $INSTALL_PREFIX. It is intended for identical Ubuntu 20.04 amd64
 machines without an existing ROS 2 Humble installation.
EOF

  cat > "$PKGROOT/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e
if command -v ldconfig >/dev/null 2>&1; then
  ldconfig
fi
exit 0
EOF

  cat > "$PKGROOT/DEBIAN/prerm" <<'EOF'
#!/usr/bin/env bash
set -e
exit 0
EOF

  chmod 0755 "$PKGROOT/DEBIAN/postinst" "$PKGROOT/DEBIAN/prerm"
}

build_deb() {
  log "Building deb"
  local deb="$ARTIFACT_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"
  dpkg-deb --build --root-owner-group "$PKGROOT" "$deb"
  dpkg-deb --info "$deb" > "$ARTIFACT_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb.info"
  dpkg-deb --contents "$deb" > "$ARTIFACT_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb.contents"
  cp "$DEPS_FILE" "$ARTIFACT_DIR/runtime-deps.txt"
  cp "$DEV_DEPS_FILE" "$ARTIFACT_DIR/dev-deps.txt"
  log "Created $deb"
}

build_marker_packages() {
  log "Building per-package ros-humble-* marker debs"
  rm -rf "$MARKER_DIR"
  mkdir -p "$MARKER_DIR"

  local package_table="$BUILD_DIR/ros-package-markers.tsv"
  python3 - "$STAGED_PREFIX" > "$package_table" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

prefix = pathlib.Path(sys.argv[1])
resource_dir = prefix / "share" / "ament_index" / "resource_index" / "packages"
for resource in sorted(resource_dir.iterdir()):
    if not resource.is_file():
        continue
    name = resource.name
    package_xml = prefix / "share" / name / "package.xml"
    if not package_xml.exists():
        continue
    try:
        version = ET.parse(package_xml).getroot().findtext("version")
    except ET.ParseError:
        continue
    if not version:
        continue
    deb_name = "ros-humble-" + name.replace("_", "-")
    print(f"{name}\t{deb_name}\t{version}")
PY

  python3 - "$package_table" > "$ROSDEP_RULES_FILE" <<'PY'
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    rows = [line.rstrip("\n").split("\t") for line in f if line.strip()]

print("# Local rosdep rules for the source-built ROS 2 Humble bundle on Ubuntu 20.04 focal.")
print("# Generated from the bundled package.xml files.")
for ros_name, deb_name, _version in rows:
    print(f"{ros_name}:")
    print("  ubuntu:")
    print("    focal:")
    print("      apt:")
    print("        packages:")
    print(f"        - {deb_name}")
PY

  local count=0
  while IFS=$'\t' read -r ros_name deb_name ros_version; do
    [ -z "$deb_name" ] && continue
    local marker_root="$BUILD_DIR/marker-root-$deb_name"
    local marker_version="${ros_version}-9999focaldummy1+${PKG_VERSION}"
    rm -rf "$marker_root"
    mkdir -p "$marker_root/DEBIAN" "$marker_root/usr/share/doc/$deb_name"
    cat > "$marker_root/DEBIAN/control" <<EOF
Package: $deb_name
Version: $marker_version
Section: misc
Priority: optional
Architecture: $PKG_ARCH
Maintainer: $MAINTAINER
Depends: $PKG_NAME (= $PKG_VERSION)
Description: Marker package for source-built ROS 2 Humble package $ros_name
 This empty package tells dpkg, apt and rosdep that $deb_name is satisfied by
 the source-built ROS 2 Humble bundle installed under $INSTALL_PREFIX.
EOF
    cat > "$marker_root/usr/share/doc/$deb_name/README" <<EOF
$deb_name is a marker package.

The actual files are provided by $PKG_NAME at $INSTALL_PREFIX.
EOF
    dpkg-deb --build --root-owner-group "$marker_root" "$MARKER_DIR/${deb_name}_${marker_version}_${PKG_ARCH}.deb" >/dev/null
    rm -rf "$marker_root"
    count=$((count + 1))
  done < "$package_table"

  tar -C "$BUILD_DIR" -czf "$MARKER_TAR" "$MARKER_SET_NAME"
  log "Created $MARKER_TAR with $count marker debs"
  log "Created $ROSDEP_RULES_FILE"
}

write_installer() {
  log "Writing installer and deployment notes"
  local installer="$ARTIFACT_DIR/install_ros2_humble.sh"
  local marker_installer="$ARTIFACT_DIR/install_ros2_humble_markers.sh"
  local deb_name
  deb_name="$(basename "$ARTIFACT_DIR"/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb)"
  local marker_tar_name
  marker_tar_name="$(basename "$MARKER_TAR")"

  cat > "$installer" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
DEB="\$SCRIPT_DIR/$deb_name"
MARKERS_TAR="\$SCRIPT_DIR/$marker_tar_name"
ROSDEP_RULES="\$SCRIPT_DIR/$ROSDEP_RULES_BASENAME"
INSTALL_PREFIX="$INSTALL_PREFIX"
ROSDEP_INDEX_URL_FILE="/etc/ros/rosdep/rosdistro_index_url"
DDS_ASSET_DIR="\$SCRIPT_DIR/pico"
INSTALL_APT_DEPS="\${INSTALL_APT_DEPS:-1}"
RUN_ROSDEP_UPDATE="\${RUN_ROSDEP_UPDATE:-1}"

configure_rosdep_network() {
  local mode="\${ROSDEP_USE_MIRROR:-auto}"
  local mirror="\${ROSDEP_ROSDISTRO_MIRROR:-https://mirrors.ustc.edu.cn/rosdistro}"
  local raw_probe="https://raw.githubusercontent.com/ros/rosdistro/master/rosdep/base.yaml"
  local default_list="/etc/ros/rosdep/sources.list.d/20-default.list"
  local mirror_hostpath="\${mirror#https://}"
  mirror_hostpath="\${mirror_hostpath#http://}"
  local tmp_list

  if [ "\$mode" = "0" ] || [ "\$mode" = "false" ]; then
    return 0
  fi
  if [ "\$mode" = "auto" ] && curl -fsSL --connect-timeout 5 --max-time 8 "\$raw_probe" >/dev/null 2>&1; then
    return 0
  fi

  tmp_list="\$(mktemp)"
  if curl -fsSL --connect-timeout 10 --max-time 30 "\$mirror/rosdep/sources.list.d/20-default.list" -o "\$tmp_list"; then
    mkdir -p /etc/ros/rosdep/sources.list.d /etc/ros/rosdep
    if [ -f "\$default_list" ] && [ ! -f "\$default_list.before-mirror" ]; then
      cp "\$default_list" "\$default_list.before-mirror"
    fi
    sed \\
      -e "s#https://raw.githubusercontent.com/ros/rosdistro/master#\$mirror#g" \\
      -e "s#http://raw.githubusercontent.com/ros/rosdistro/master#\$mirror#g" \\
      -e "s#raw.githubusercontent.com/ros/rosdistro/master#\$mirror_hostpath#g" \\
      "\$tmp_list" > "\$default_list"
    printf '%s\n' "\$mirror/index-v4.yaml" > "\$ROSDEP_INDEX_URL_FILE"
    echo "Configured rosdep rosdistro mirror: \$mirror"
  else
    echo "Warning: raw.githubusercontent.com is unreachable and mirror setup failed: \$mirror" >&2
  fi
  rm -f "\$tmp_list"
}

run_rosdep_update() {
  local index_url=""
  if [ -f "\$ROSDEP_INDEX_URL_FILE" ]; then
    index_url="\$(head -n 1 "\$ROSDEP_INDEX_URL_FILE")"
  fi

  if [ -n "\${SUDO_USER:-}" ] && [ "\$SUDO_USER" != "root" ]; then
    if [ -n "\$index_url" ]; then
      su - "\$SUDO_USER" -c "ROSDISTRO_INDEX_URL=\$index_url rosdep update" || ROSDISTRO_INDEX_URL="\$index_url" rosdep update || true
    else
      su - "\$SUDO_USER" -c 'rosdep update' || rosdep update || true
    fi
  else
    if [ -n "\$index_url" ]; then
      ROSDISTRO_INDEX_URL="\$index_url" rosdep update || true
    else
      rosdep update || true
    fi
  fi
}

install_rosdep_rules() {
  if [ ! -f "\$ROSDEP_RULES" ]; then
    return 0
  fi
  configure_rosdep_network
  mkdir -p /etc/ros/rosdep /etc/ros/rosdep/sources.list.d
  install -m 0644 "\$ROSDEP_RULES" /etc/ros/rosdep/$ROSDEP_RULES_BASENAME
  cat > /etc/ros/rosdep/sources.list.d/50-ros2-humble-focal-source-build.list <<'RULEEOF'
yaml file:///etc/ros/rosdep/$ROSDEP_RULES_BASENAME
RULEEOF
  if [ "\$RUN_ROSDEP_UPDATE" != "0" ] && command -v rosdep >/dev/null 2>&1; then
    run_rosdep_update
  fi
}

install_pico_runtime_assets() {
  if [ ! -d "\$DDS_ASSET_DIR" ]; then
    return 0
  fi

  echo "Installing Pico CycloneDDS deployment assets from \$DDS_ASSET_DIR"
  mkdir -p /etc/ros/cyclonedds /etc/ros /opt/zj_humanoid/tools

  if [ -f "\$DDS_ASSET_DIR/pico-cyclonedds.xml" ]; then
    install -m 0644 "\$DDS_ASSET_DIR/pico-cyclonedds.xml" /etc/ros/cyclonedds/pico-cyclonedds.xml
  fi
  if [ -f "\$DDS_ASSET_DIR/10-ros2-dds.conf" ]; then
    install -m 0644 "\$DDS_ASSET_DIR/10-ros2-dds.conf" /etc/sysctl.d/10-ros2-dds.conf
    sysctl --system || true
  fi
  if [ -f "\$DDS_ASSET_DIR/ros2_link_test.py" ]; then
    install -m 0755 "\$DDS_ASSET_DIR/ros2_link_test.py" /opt/zj_humanoid/tools/ros2_link_test.py
  fi
  if [ -f "\$DDS_ASSET_DIR/source_ros2_humble_clean.bash" ]; then
    install -m 0644 "\$DDS_ASSET_DIR/source_ros2_humble_clean.bash" /etc/ros/source_ros2_humble_clean.bash
    install -m 0644 "\$DDS_ASSET_DIR/source_ros2_humble_clean.bash" /opt/zj_humanoid/tools/source_ros2_humble_clean.bash
  fi

  cat > /etc/ros/ros2_humble_cyclone.env <<'ENVEOF'
ROS_DOMAIN_ID=20
ROS_LOCALHOST_ONLY=0
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
CYCLONEDDS_URI=file:///etc/ros/cyclonedds/pico-cyclonedds.xml
ENVEOF

  cat > /etc/profile.d/ros2_humble_cyclone.sh <<'PROFILEEOF'
# ROS 2 Humble DDS defaults for ZJ Humanoid Pico.
# This file intentionally exports only DDS/RMW variables. Startup scripts should
# source /opt/ros/humble/setup.bash explicitly before launching ROS 2 nodes.
export ROS_DOMAIN_ID="\${ROS_DOMAIN_ID:-20}"
export ROS_LOCALHOST_ONLY="\${ROS_LOCALHOST_ONLY:-0}"
export RMW_IMPLEMENTATION="\${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"
export CYCLONEDDS_URI="\${CYCLONEDDS_URI:-file:///etc/ros/cyclonedds/pico-cyclonedds.xml}"
PROFILEEOF

  chmod 0644 /etc/ros/ros2_humble_cyclone.env /etc/profile.d/ros2_humble_cyclone.sh
}

cmake_version_for_user() {
  local target_user="\$1"
  if [ "\$target_user" = "root" ]; then
    PATH="/root/.local/bin:\$PATH" cmake --version 2>/dev/null | awk '/version/ {print \$3; exit}' || true
  else
    su - "\$target_user" -c 'PATH="\$HOME/.local/bin:\$PATH"; cmake --version 2>/dev/null | awk "/version/ {print \\\$3; exit}"' || true
  fi
}

install_user_cmake_for_overlay() {
  if [ "\${INSTALL_OVERLAY_TOOLS:-1}" = "0" ]; then
    return 0
  fi

  local target_user="\${SUDO_USER:-root}"
  if ! id "\$target_user" >/dev/null 2>&1; then
    target_user="root"
  fi

  local current_version
  current_version="\$(cmake_version_for_user "\$target_user")"
  if [ -n "\$current_version" ] && dpkg --compare-versions "\$current_version" ge 3.22; then
    echo "Overlay CMake for \$target_user is new enough: \$current_version"
    return 0
  fi

  echo "Installing user-level CMake >= 3.22 for overlay builds as \$target_user."
  if [ "\$target_user" = "root" ]; then
    python3 -m pip install --user 'cmake>=3.22,<3.29' || {
      echo "Warning: failed to install newer CMake with pip. Overlay packages such as ros2_control may need CMake >= 3.22." >&2
      return 0
    }
  else
    su - "\$target_user" -c 'python3 -m pip install --user "cmake>=3.22,<3.29"' || {
      echo "Warning: failed to install newer CMake with pip. Overlay packages such as ros2_control may need CMake >= 3.22." >&2
      return 0
    }
  fi

  current_version="\$(cmake_version_for_user "\$target_user")"
  if [ -n "\$current_version" ] && dpkg --compare-versions "\$current_version" ge 3.22; then
    echo "Installed overlay CMake for \$target_user: \$current_version"
  else
    echo "Warning: newer CMake was not found after pip install. Add ~/.local/bin to PATH before building overlays." >&2
  fi
}

install_deb_or_fix_deps() {
  if dpkg -i "\$@"; then
    return 0
  fi

  if [ "\$INSTALL_APT_DEPS" = "0" ]; then
    echo "dpkg failed while INSTALL_APT_DEPS=0; not running online apt fixup." >&2
    echo "Install the bundled apt dependencies first, then rerun this installer." >&2
    return 1
  fi

  apt-get -f install -y
}

if [ "\$(id -u)" -ne 0 ]; then
  echo "Please run with sudo: sudo \$0" >&2
  exit 1
fi

. /etc/os-release
if [ "\${VERSION_CODENAME:-}" != "focal" ]; then
  echo "This package is for Ubuntu 20.04 focal only; got \${PRETTY_NAME:-unknown}" >&2
  exit 1
fi

if [ "\$(dpkg --print-architecture)" != "amd64" ]; then
  echo "This package is for amd64 only; got \$(dpkg --print-architecture)" >&2
  exit 1
fi

if dpkg -l 'ros-humble-*' 2>/dev/null | awk '/^ii/{found=1} END{exit found ? 0 : 1}'; then
  echo "Existing ros-humble-* Debian packages were found. Refusing to mix installations." >&2
  exit 1
fi

if [ -e "\$INSTALL_PREFIX" ] && [ -n "\$(find "\$INSTALL_PREFIX" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
  echo "\$INSTALL_PREFIX already exists and is not empty. Move it away before installing." >&2
  exit 1
fi

if [ "\$INSTALL_APT_DEPS" != "0" ]; then
  apt-get update
  apt-get install -y \$(tr '\n' ' ' < "\$SCRIPT_DIR/runtime-deps.txt")

  if [ -f "\$SCRIPT_DIR/dev-deps.txt" ]; then
    dev_install=()
    dev_missing=()
    while IFS= read -r pkg; do
      [ -z "\$pkg" ] && continue
      if apt-cache show "\$pkg" >/dev/null 2>&1; then
        dev_install+=("\$pkg")
      else
        dev_missing+=("\$pkg")
      fi
    done < "\$SCRIPT_DIR/dev-deps.txt"

    if [ "\${#dev_install[@]}" -gt 0 ]; then
      apt-get install -y "\${dev_install[@]}"
    fi
    if [ "\${#dev_missing[@]}" -gt 0 ]; then
      echo "Some optional overlay build packages are not visible in apt:" >&2
      printf '  %s\n' "\${dev_missing[@]}" >&2
      echo "Runtime install continues; install the missing tools separately before building overlay packages." >&2
    fi
  fi
else
  echo "INSTALL_APT_DEPS=0: skipping apt runtime/dev dependency installation."
fi
install_user_cmake_for_overlay

install_deb_or_fix_deps "\$DEB"

if [ -f "\$MARKERS_TAR" ]; then
  marker_tmp="\$(mktemp -d)"
  trap 'rm -rf "\$marker_tmp"' EXIT
  tar -xzf "\$MARKERS_TAR" -C "\$marker_tmp"
  install_deb_or_fix_deps "\$marker_tmp"/*/*.deb
fi
install_rosdep_rules
install_pico_runtime_assets

cat <<MSG

ROS 2 Humble installed at \$INSTALL_PREFIX

Use:
  source \$INSTALL_PREFIX/setup.bash
  source /etc/profile.d/ros2_humble_cyclone.sh

For overlay workspaces:
  source \$INSTALL_PREFIX/setup.bash
  mkdir -p ~/ros2_overlay/src
  cd ~/ros2_overlay
  if command -v rosdep >/dev/null 2>&1; then
    rosdep install --from-paths src --ignore-src -y --os=ubuntu:focal --rosdistro humble
  fi
  export PATH=\$HOME/.local/bin:\$PATH
  colcon build --symlink-install
  source install/setup.bash

MSG
EOF
  chmod 0755 "$installer"

  cat > "$marker_installer" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
MARKERS_TAR="\$SCRIPT_DIR/$marker_tar_name"
ROSDEP_RULES="\$SCRIPT_DIR/$ROSDEP_RULES_BASENAME"
REQUIRED_BUNDLE="$PKG_NAME"
REQUIRED_VERSION="$PKG_VERSION"
ROSDEP_INDEX_URL_FILE="/etc/ros/rosdep/rosdistro_index_url"

configure_rosdep_network() {
  local mode="\${ROSDEP_USE_MIRROR:-auto}"
  local mirror="\${ROSDEP_ROSDISTRO_MIRROR:-https://mirrors.ustc.edu.cn/rosdistro}"
  local raw_probe="https://raw.githubusercontent.com/ros/rosdistro/master/rosdep/base.yaml"
  local default_list="/etc/ros/rosdep/sources.list.d/20-default.list"
  local mirror_hostpath="\${mirror#https://}"
  mirror_hostpath="\${mirror_hostpath#http://}"
  local tmp_list

  if [ "\$mode" = "0" ] || [ "\$mode" = "false" ]; then
    return 0
  fi
  if [ "\$mode" = "auto" ] && curl -fsSL --connect-timeout 5 --max-time 8 "\$raw_probe" >/dev/null 2>&1; then
    return 0
  fi

  tmp_list="\$(mktemp)"
  if curl -fsSL --connect-timeout 10 --max-time 30 "\$mirror/rosdep/sources.list.d/20-default.list" -o "\$tmp_list"; then
    mkdir -p /etc/ros/rosdep/sources.list.d /etc/ros/rosdep
    if [ -f "\$default_list" ] && [ ! -f "\$default_list.before-mirror" ]; then
      cp "\$default_list" "\$default_list.before-mirror"
    fi
    sed \\
      -e "s#https://raw.githubusercontent.com/ros/rosdistro/master#\$mirror#g" \\
      -e "s#http://raw.githubusercontent.com/ros/rosdistro/master#\$mirror#g" \\
      -e "s#raw.githubusercontent.com/ros/rosdistro/master#\$mirror_hostpath#g" \\
      "\$tmp_list" > "\$default_list"
    printf '%s\n' "\$mirror/index-v4.yaml" > "\$ROSDEP_INDEX_URL_FILE"
    echo "Configured rosdep rosdistro mirror: \$mirror"
  else
    echo "Warning: raw.githubusercontent.com is unreachable and mirror setup failed: \$mirror" >&2
  fi
  rm -f "\$tmp_list"
}

run_rosdep_update() {
  local index_url=""
  if [ -f "\$ROSDEP_INDEX_URL_FILE" ]; then
    index_url="\$(head -n 1 "\$ROSDEP_INDEX_URL_FILE")"
  fi

  if [ -n "\${SUDO_USER:-}" ] && [ "\$SUDO_USER" != "root" ]; then
    if [ -n "\$index_url" ]; then
      su - "\$SUDO_USER" -c "ROSDISTRO_INDEX_URL=\$index_url rosdep update" || ROSDISTRO_INDEX_URL="\$index_url" rosdep update || true
    else
      su - "\$SUDO_USER" -c 'rosdep update' || rosdep update || true
    fi
  else
    if [ -n "\$index_url" ]; then
      ROSDISTRO_INDEX_URL="\$index_url" rosdep update || true
    else
      rosdep update || true
    fi
  fi
}

install_rosdep_rules() {
  if [ ! -f "\$ROSDEP_RULES" ]; then
    return 0
  fi
  configure_rosdep_network
  mkdir -p /etc/ros/rosdep /etc/ros/rosdep/sources.list.d
  install -m 0644 "\$ROSDEP_RULES" /etc/ros/rosdep/$ROSDEP_RULES_BASENAME
  cat > /etc/ros/rosdep/sources.list.d/50-ros2-humble-focal-source-build.list <<'RULEEOF'
yaml file:///etc/ros/rosdep/$ROSDEP_RULES_BASENAME
RULEEOF
  if command -v rosdep >/dev/null 2>&1; then
    run_rosdep_update
  fi
}

if [ "\$(id -u)" -ne 0 ]; then
  echo "Please run with sudo: sudo \$0" >&2
  exit 1
fi

if [ ! -f "\$MARKERS_TAR" ]; then
  echo "Missing marker archive: \$MARKERS_TAR" >&2
  exit 1
fi

installed_version="\$(dpkg-query -W -f='\${Version}' "\$REQUIRED_BUNDLE" 2>/dev/null || true)"
if [ "\$installed_version" != "\$REQUIRED_VERSION" ]; then
  echo "\$REQUIRED_BUNDLE \$REQUIRED_VERSION must be installed first; found '\${installed_version:-not installed}'." >&2
  exit 1
fi

marker_tmp="\$(mktemp -d)"
trap 'rm -rf "\$marker_tmp"' EXIT
tar -xzf "\$MARKERS_TAR" -C "\$marker_tmp"
dpkg -i "\$marker_tmp"/*/*.deb || apt-get -f install -y
install_rosdep_rules

echo "Installed ros-humble-* marker packages for the source-built ROS 2 Humble bundle."
EOF
  chmod 0755 "$marker_installer"

  cat > "$ARTIFACT_DIR/README_DEPLOY.md" <<EOF
# ROS 2 Humble Focal Desktop Bundle

Built from source on Ubuntu 20.04 amd64.

## Files

- \`$deb_name\`: ROS 2 Humble desktop install tree under \`$INSTALL_PREFIX\`
- \`$marker_tar_name\`: empty per-package \`ros-humble-*\` marker debs for apt/rosdep dependency resolution
- \`$ROSDEP_RULES_BASENAME\`: local Focal rosdep mappings for bundled ROS package keys
- \`runtime-deps.txt\`: Ubuntu runtime dependency package list
- \`dev-deps.txt\`: optional overlay build tool dependency package list
- \`install_ros2_humble.sh\`: guarded installer for clean machines
- \`install_ros2_humble_markers.sh\`: marker-only installer for a machine where the main bundle is already installed
- \`pico/\`: Pico CycloneDDS XML, DDS sysctl tuning, environment loader, and link-test tool

## Install

\`\`\`bash
sudo ./install_ros2_humble.sh
source $INSTALL_PREFIX/setup.bash
source /etc/profile.d/ros2_humble_cyclone.sh
\`\`\`

The installer refuses to run if existing \`ros-humble-*\` Debian packages or a
non-empty \`$INSTALL_PREFIX\` are present.

When \`pico/\` is present, the installer also writes:

\`\`\`text
/etc/ros/cyclonedds/pico-cyclonedds.xml
/etc/ros/ros2_humble_cyclone.env
/etc/ros/source_ros2_humble_clean.bash
/etc/profile.d/ros2_humble_cyclone.sh
/etc/sysctl.d/10-ros2-dds.conf
/opt/zj_humanoid/tools/ros2_link_test.py
/opt/zj_humanoid/tools/source_ros2_humble_clean.bash
\`\`\`

## Validate

\`\`\`bash
source $INSTALL_PREFIX/setup.bash
source /etc/profile.d/ros2_humble_cyclone.sh
./verify_installed_humble_env.sh
ros2 pkg prefix rviz2
ros2 run demo_nodes_cpp talker
\`\`\`

In another terminal:

\`\`\`bash
source $INSTALL_PREFIX/setup.bash
ros2 topic echo --once /chatter std_msgs/msg/String
\`\`\`

## Overlay packages

\`\`\`bash
source $INSTALL_PREFIX/setup.bash
mkdir -p ~/ros2_overlay/src
cd ~/ros2_overlay/src
# git clone or copy third-party packages here
cd ~/ros2_overlay
if command -v rosdep >/dev/null 2>&1; then
  rosdep install --from-paths src --ignore-src -y --os=ubuntu:focal --rosdistro humble
else
  echo "rosdep is not installed; install declared apt/vendor dependencies from the offline bundle first."
fi
export PATH=\$HOME/.local/bin:\$PATH
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
source install/setup.bash
\`\`\`

The marker debs make commands such as \`dpkg -l 'ros-humble-*'\`, \`apt list
--installed 'ros-humble-*'\`, and \`rosdep install\` see the source-built ROS
packages as installed Debian packages. They contain no ROS files; the actual
files remain in \`$INSTALL_PREFIX\` from the main bundle.

Because ROS 2 Humble is normally mapped to Ubuntu Jammy in upstream rosdep, the
installer also registers a local Focal rosdep rule file for the bundled package
keys.

For third-party ROS packages on Focal, clone their ROS dependencies into the
same workspace as source packages when no Ubuntu 20.04 Humble deb exists. For
example, official \`ros2_control\` needs source dependencies such as
\`control_msgs\`, \`control_toolbox\`, \`realtime_tools\`,
\`generate_parameter_library\`, \`RSL\`, and \`backward_ros\`. Then run
\`rosdep install --from-paths src --ignore-src --os=ubuntu:focal --rosdistro humble -y\`.
The installer adds user-level CMake 3.22+ for these overlays because Ubuntu
20.04's apt CMake is too old for parts of the current ros2_control dependency
tree.

If \`rosdep update\` times out on \`raw.githubusercontent.com\`, it does not
break the installed ROS files or marker packages, but rosdep's cache may be
incomplete. The installer defaults to \`ROSDEP_USE_MIRROR=auto\`: when GitHub raw
is unreachable it rewrites rosdep's default source list to the USTC rosdistro
mirror and stores \`https://mirrors.ustc.edu.cn/rosdistro/index-v4.yaml\` in
\`/etc/ros/rosdep/rosdistro_index_url\`. You can force a mirror with
\`ROSDEP_USE_MIRROR=1\`, disable this with \`ROSDEP_USE_MIRROR=0\`, or override the
mirror with \`ROSDEP_ROSDISTRO_MIRROR=<url>\`.

The local source-build rule is installed at
\`/etc/ros/rosdep/rosdep-humble-focal-source-build.yaml\`.
EOF
}

main() {
  require_focal_amd64
  require_packaging_tools
  if [ ! -f "$SRC_PREFIX/setup.bash" ]; then
    echo "Missing source ROS setup.bash at $SRC_PREFIX/setup.bash" >&2
    exit 1
  fi
  prepare_dirs
  copy_install_space
  relocate_install_space
  scan_runtime_deps
  write_control_files
  build_deb
  build_marker_packages
  write_installer
  log "Artifacts:"
  ls -lh "$ARTIFACT_DIR"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
