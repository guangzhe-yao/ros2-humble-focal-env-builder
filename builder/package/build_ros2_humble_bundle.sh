#!/usr/bin/env bash
set -Eeuo pipefail

SRC_PREFIX="${SRC_PREFIX:-$HOME/ros2_humble/install_deploy}"
OUT_DIR="${OUT_DIR:-$HOME/ros2_humble_deploy}"
PKG_NAME="${PKG_NAME:-ros2-humble-focal-desktop-source}"
PKG_VERSION="${PKG_VERSION:-0.3.3+$(date +%Y%m%d%H%M)}"
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
    --allowlist "$(dirname "${BASH_SOURCE[0]}")/../../profiles/humble-environment-packages.txt" \
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
cmake
git
mawk
libasio-dev
libboost-filesystem-dev
libboost-regex-dev
libboost-serialization-dev
libboost-thread-dev
libconsole-bridge-dev
libeigen3-dev
libfmt-dev
libgoogle-glog-dev
libgtest-dev
libgmock-dev
libhdf5-dev
libnl-3-dev
libspdlog-dev
libssl-dev
libtinyxml-dev
libtinyxml2-dev
liburdfdom-dev
liburdfdom-headers-dev
libyaml-cpp-dev
libzmq3-dev
pkg-config
python3-colcon-common-extensions
python3-dev
python3-pip
python3-vcstool
python3-venv
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
  log "Artifacts:"
  ls -lh "$ARTIFACT_DIR"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
