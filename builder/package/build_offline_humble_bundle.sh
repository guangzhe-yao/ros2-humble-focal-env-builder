#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$HOME/ros2_humble_unified/package_out/artifacts}"
OUT_DIR="${OUT_DIR:-$ARTIFACT_DIR/offline}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$(date +%Y%m%d%H%M)}"
PKG_ARCH="${PKG_ARCH:-$(dpkg --print-architecture)}"
BUNDLE_NAME="${BUNDLE_NAME:-ros2-humble-focal-offline-bundle_${BUNDLE_VERSION}_${PKG_ARCH}}"
INCLUDE_DEV_DEPS="${INCLUDE_DEV_DEPS:-1}"
APT_INCLUDE_RECOMMENDS="${APT_INCLUDE_RECOMMENDS:-0}"
APT_DOWNLOAD_TIMEOUT="${APT_DOWNLOAD_TIMEOUT:-300}"
APT_DOWNLOAD_RETRIES="${APT_DOWNLOAD_RETRIES:-3}"
ENABLE_OSRF_GAZEBO_SOURCE="${ENABLE_OSRF_GAZEBO_SOURCE:-1}"
OSRF_GAZEBO_APT_SOURCE="${OSRF_GAZEBO_APT_SOURCE:-deb [trusted=yes] http://packages.osrfoundation.org/gazebo/ubuntu-stable focal main}"
APT_EXCLUDED_PACKAGES_REGEX="${APT_EXCLUDED_PACKAGES_REGEX:-^(python3-rosdep|python3-rosdep2)$}"
EXTRA_APT_ROOT_DEPS_FILE="${EXTRA_APT_ROOT_DEPS_FILE:-}"
EXTRA_APT_DEBS_DIR="${EXTRA_APT_DEBS_DIR:-}"

BUNDLE_ROOT="$OUT_DIR/$BUNDLE_NAME"
APT_DEBS_DIR="$BUNDLE_ROOT/apt_debs"
BUNDLE_ARTIFACT_DIR="$BUNDLE_ROOT/artifacts"
DEPS_ROOT_FILE="$BUNDLE_ROOT/apt-root-deps.txt"
DEPS_CANDIDATES_FILE="$BUNDLE_ROOT/apt-dependency-candidates.txt"
DEPS_CLOSURE_FILE="$BUNDLE_ROOT/apt-closure-deps.txt"
MISSING_DEPS_FILE="$BUNDLE_ROOT/apt-unavailable-candidates.txt"
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
  compgen -G "$ARTIFACT_DIR/ros2-humble-focal-desktop-source_*_${PKG_ARCH}.deb" >/dev/null || missing+=("main ros2-humble deb")
  compgen -G "$ARTIFACT_DIR/ros-humble-package-markers_*_${PKG_ARCH}.tar.gz" >/dev/null || missing+=("marker tar")
  [ -f "$ARTIFACT_DIR/runtime-deps.txt" ] || missing+=("$ARTIFACT_DIR/runtime-deps.txt")
  if [[ "$INCLUDE_DEV_DEPS" == 1 && ! -f "$ARTIFACT_DIR/dev-deps.txt" ]]; then
    missing+=("$ARTIFACT_DIR/dev-deps.txt")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing generated artifacts:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi
  local -a bases=("$ARTIFACT_DIR"/ros2-humble-focal-desktop-source_*_"$PKG_ARCH".deb)
  local -a markers=("$ARTIFACT_DIR"/ros-humble-package-markers_*_"$PKG_ARCH".tar.gz)
  [[ ${#bases[@]} -eq 1 && ${#markers[@]} -eq 1 ]] || {
    echo 'Expected exactly one base DEB and one matching marker archive' >&2; return 1;
  }
  local version architecture name
  version="$(dpkg-deb -f "${bases[0]}" Version)"
  architecture="$(dpkg-deb -f "${bases[0]}" Architecture)"
  name="$(dpkg-deb -f "${bases[0]}" Package)"
  [[ "$name" == ros2-humble-focal-desktop-source && "$architecture" == "$PKG_ARCH" &&
     "${bases[0]}" == "$ARTIFACT_DIR/${name}_${version}_${architecture}.deb" &&
     "${markers[0]}" == "$ARTIFACT_DIR/ros-humble-package-markers_${version}_${architecture}.tar.gz" ]] || {
    echo 'Base DEB metadata and marker archive version/architecture must match' >&2; return 1;
  }
}

prepare_bundle_root() {
  [[ "$BUNDLE_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]] || {
    echo 'BUNDLE_NAME must be a single directory name, not a path' >&2; return 1;
  }
  local destination
  for destination in "$BUNDLE_ROOT" "$BUNDLE_ROOT.tar.gz" "$BUNDLE_ROOT.tar.gz.sha256"; do
    [[ ! -e "$destination" && ! -L "$destination" ]] || {
      echo "Refusing to replace existing output: $destination; use a new version" >&2; return 1;
    }
  done
  log "Preparing offline bundle root: $BUNDLE_ROOT"
  mkdir -p "$OUT_DIR"
  mkdir "$BUNDLE_ROOT" || return 1
  mkdir -p "$APT_DEBS_DIR" "$BUNDLE_ARTIFACT_DIR"
  cp "$ARTIFACT_DIR"/ros2-humble-focal-desktop-source_*_"$PKG_ARCH".deb "$APT_DEBS_DIR/"
  local marker_temp metadata
  marker_temp="$(mktemp -d)"
  for metadata in "$ARTIFACT_DIR"/ros-humble-package-markers_*_"$PKG_ARCH".tar.gz; do
    tar -xzf "$metadata" -C "$marker_temp"
  done
  find "$marker_temp" -type f -name '*.deb' -exec cp -t "$APT_DEBS_DIR" {} +
  rm -rf "$marker_temp"
  for metadata in runtime-deps.txt dev-deps.txt source-lock.repos third_party.repos build-provenance.json rosdep-humble-focal-source-build.yaml; do
    [[ ! -f "$ARTIFACT_DIR/$metadata" ]] || cp "$ARTIFACT_DIR/$metadata" "$BUNDLE_ARTIFACT_DIR/"
  done
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
    deps="$(dpkg-deb -f "$deb" "$field")"
    [[ -n "$deps" ]] || continue
    # Dpkg::Deps comes with dpkg-dev, already required by dpkg-scanpackages.
    perl -MDpkg::Deps -e '
      my $deps = deps_parse($ARGV[0]);
      defined $deps or die "Invalid DEB dependencies\n";
      deps_iterate($deps, sub {
        my ($dep) = @_;
        print $dep->{package};
        print ":$dep->{archqual}" if defined $dep->{archqual};
        print "\n";
        return 1;
      });
    ' "$deps"
  done
}

emit_artifact_deb_candidates() {
  local deb
  while IFS= read -r -d '' deb; do
    emit_deb_dependency_names "$deb"
  done < <(
    find "$ARTIFACT_DIR" -maxdepth 1 -type f \
      -name "ros2-humble-focal-desktop-source_*_${PKG_ARCH}.deb" -print0
  )
}

emit_extra_deb_inputs() {
  local mode="$1"
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
      if [[ "$mode" == roots ]]; then
        dpkg-deb -f "$deb" Package
      else
        emit_deb_dependency_names "$deb"
      fi
    done < <(find "$extra_dir" -maxdepth 1 -type f -name '*.deb' -print0)
  done
}

collect_root_deps() {
  log "Collecting root apt dependency package names"
  {
    sed '/^$/d' "$ARTIFACT_DIR/runtime-deps.txt"
    if [ "$INCLUDE_DEV_DEPS" = "1" ] && [ -f "$ARTIFACT_DIR/dev-deps.txt" ]; then
      sed '/^$/d' "$ARTIFACT_DIR/dev-deps.txt"
    fi
    emit_extra_root_deps_files
    emit_extra_deb_inputs roots
  } | awk -v re="$APT_EXCLUDED_PACKAGES_REGEX" 'NF && (re == "" || $0 !~ re)' \
    | sort -u > "$DEPS_ROOT_FILE"
  # Alternatives are download candidates, not independent install requests.
  {
    cat "$DEPS_ROOT_FILE"
    emit_artifact_deb_candidates
    emit_extra_deb_inputs candidates
  } | sort -u > "$DEPS_CANDIDATES_FILE"
}

copy_extra_apt_debs() {
  local directory deb name provided wanted
  local -a directories=()
  declare -A required=()
  while IFS= read -r name; do
    name="${name%:any}"; name="${name%:amd64}"
    [[ -z "$name" ]] || required["$name"]=1
  done < "$DEPS_CLOSURE_FILE"
  IFS=':' read -r -a directories <<< "${CACHED_APT_DEBS_DIR:-}"
  for directory in "${directories[@]}"; do
    [[ -z "$directory" ]] && continue
    [[ -d "$directory" ]] || { echo "Missing cache: $directory" >&2; return 1; }
    while IFS= read -r -d '' deb; do
      name="$(dpkg-deb -f "$deb" Package)"
      # Cached robot releases must never reintroduce business/vendor packages.
      case "$name" in zj-*|robotpkg-*|ros-*|ros2-*) continue;; esac
      wanted="${required[$name]:-}"
      while IFS= read -r provided; do
        [[ -z "$provided" ]] || wanted="$wanted${required[$provided]:-}"
      done < <(dpkg-deb -f "$deb" Provides | tr ',' '\n' | awk '{print $1}')
      [[ -z "$wanted" ]] || cp "$deb" "$APT_DEBS_DIR/"
    done < <(find "$directory" -maxdepth 1 -name '*.deb' -print0)
  done
  IFS=':' read -r -a directories <<< "$EXTRA_APT_DEBS_DIR"
  for directory in "${directories[@]}"; do
    [[ -z "$directory" ]] && continue
    [[ -d "$directory" ]] || { echo "Missing DEB directory: $directory" >&2; return 1; }
    find "$directory" -maxdepth 1 -type f -name '*.deb' -exec cp -t "$APT_DEBS_DIR" {} +
  done
}

assert_environment_debs() {
  local deb name
  for deb in "$APT_DEBS_DIR"/*.deb; do
    name="$(dpkg-deb -f "$deb" Package)"
    case "$name" in
      zj-*|robotpkg-*|xenomai*|libxenomai*|ros-humble-navi-*|ros-humble-robot-nodes*|ros-humble-legged-*|ros-humble-uplimb-*|ros-humble-upperlimb-*)
        echo "Business/vendor package is not part of the Humble environment: $name" >&2
        return 1;;
    esac
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
  mapfile -t queue < "$DEPS_CANDIDATES_FILE"
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
  # Local/vendor packages often have no downloadable apt candidate. Their
  # metadata is authoritative; the final offline solver checks constraints.
  local supplied_deb supplied_name
  declare -A supplied_packages=()
  while IFS= read -r -d '' supplied_deb; do
    supplied_name="$(dpkg-deb -f "$supplied_deb" Package)"
    supplied_packages["$supplied_name"]=1
    while IFS= read -r supplied_name; do
      [[ -z "$supplied_name" ]] || supplied_packages["$supplied_name"]=1
    done < <(dpkg-deb -f "$supplied_deb" Provides | tr ',' '\n' | awk '{print $1}')
  done < <(find "$APT_DEBS_DIR" -maxdepth 1 -name '*.deb' -print0)
  pushd "$APT_DEBS_DIR" >/dev/null

  local attempt candidate pkg
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    local lookup_name="${pkg%:any}"
    lookup_name="${lookup_name%:amd64}"
    if [[ -n "${supplied_packages[$lookup_name]+present}" ]]; then
      continue
    fi
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
        awk|dbus-session-bus|debconf-2.0|default-dbus-session-bus|fonts-freefont|gsettings-backend|libblas.so.3|liblapack.so.3|libopencl-1.1-1|libopencl-1.2-1|libopencl1|python3:any|python3.8:any|qtbase-abi-*|qtdeclarative-abi-*|time-daemon)
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
    echo "The offline apt solver will verify required dependencies and alternatives before release." >&2
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
  # Parse control records rather than concatenate them: vendor controls may
  # contain trailing blank lines which would split Filename into a new record.
  dpkg-scanpackages --multiversion . /dev/null > Packages
  gzip -kf Packages
  popd >/dev/null
}

write_offline_installer() {
  local repo
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  cp "$repo/deploy/pico/install_humble_environment.sh" "$BUNDLE_ROOT/install.sh"
  local base
  local -a bases=("$APT_DEBS_DIR"/ros2-humble-focal-desktop-source_*.deb)
  [[ ${#bases[@]} -eq 1 && -f "${bases[0]}" ]] || { echo 'Expected one base DEB' >&2; return 1; }
  base="${bases[0]}"
  dpkg-deb --fsys-tarfile "$base" | tar -tf - \
    | awk '/\/share\/ament_index\/resource_index\/packages\/[^/]+$/ {sub(".*/", ""); print}' \
    | sort -u > "$BUNDLE_ROOT/ros-packages.txt"
  chmod +x "$BUNDLE_ROOT/install.sh"
  {
    cat "$DEPS_ROOT_FILE"
    for deb in "$APT_DEBS_DIR"/ros2-humble-focal-desktop-source_*.deb "$APT_DEBS_DIR"/ros-humble-*.deb; do
      [[ -f "$deb" ]] || continue
      printf '%s=%s\n' "$(dpkg-deb -f "$deb" Package)" "$(dpkg-deb -f "$deb" Version)"
    done
  } | sort -u > "$BUNDLE_ROOT/root-packages.txt"
}

write_readme() {
  local repo
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  cp "$repo/deploy/pico/README_OFFLINE.zh-CN.md" "$BUNDLE_ROOT/README.md"
  mkdir -p "$BUNDLE_ROOT/configuration"
  cp "$repo"/profiles/apt-*.txt "$repo"/profiles/pico-*.txt \
    "$repo/profiles/ros1-migration.json" "$repo/profiles/excluded-components.txt" \
    "$repo/profiles/humble-environment-packages.txt" "$BUNDLE_ROOT/configuration/"
  python3 "$repo/builder/package/write_inventory.py" "$BUNDLE_ROOT" > "$BUNDLE_ROOT/manifest.json"
  (
    cd "$BUNDLE_ROOT"
    find apt_debs artifacts configuration -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
    sha256sum manifest.json >> SHA256SUMS
    sha256sum install.sh root-packages.txt ros-packages.txt README.md >> SHA256SUMS
  )
}

validate_offline_dependencies() (
  # Resolve against an empty installed-package database, not the build host.
  # Missing alternatives/providers are not necessarily missing dependencies.
  local temp
  temp="$(mktemp -d)"
  trap 'rm -rf "$temp"' EXIT
  mkdir -p "$temp/lists/partial" "$temp/parts" "$temp/archives/partial"
  : > "$temp/status"
  printf 'deb [trusted=yes] file:%s ./\n' "$APT_DEBS_DIR" > "$temp/sources.list"
  local opts=(-o "Dir::Etc::sourcelist=$temp/sources.list"
              -o "Dir::Etc::sourceparts=$temp/parts"
              -o "Dir::State::Lists=$temp/lists"
              -o "Dir::State::status=$temp/status"
              -o "Dir::Cache::archives=$temp/archives"
              -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache=
              -o "APT::Sandbox::User=$(id -un)" -o Acquire::Languages=none)
  local -a roots
  mapfile -t roots < "$BUNDLE_ROOT/root-packages.txt"
  log "Validating offline dependencies with an empty package database"
  apt-get "${opts[@]}" update > "$BUNDLE_ROOT/dependency-resolution.log" 2>&1
  apt-get "${opts[@]}" -s --no-remove --no-install-recommends install "${roots[@]}" \
    >> "$BUNDLE_ROOT/dependency-resolution.log" 2>&1
)

make_tarball() (
  log "Creating tarball"
  local tarball="$OUT_DIR/$BUNDLE_NAME.tar.gz"
  [[ ! -e "$tarball" && ! -L "$tarball" && ! -e "$tarball.sha256" && ! -L "$tarball.sha256" ]] || {
    echo "Refusing to replace release: $tarball" >&2; return 1;
  }
  local temp digest
  temp="$(mktemp "$OUT_DIR/.bundle.XXXXXX")"
  trap 'rm -f "$temp" "$temp.sha256"' EXIT
  tar -C "$OUT_DIR" -czf "$temp" "$BUNDLE_NAME" || return 1
  digest="$(sha256sum "$temp")" || return 1
  printf '%s  %s\n' "${digest%% *}" "$(basename "$tarball")" > "$temp.sha256" || return 1
  chmod 0644 "$temp" "$temp.sha256" || return 1
  ln "$temp" "$tarball" || return 1
  ln "$temp.sha256" "$tarball.sha256" || return 1
  log "Offline candidate created (latest unchanged): $tarball"
  log "SHA256: $tarball.sha256"
)

main() {
  require_focal_amd64
  require_artifacts
  prepare_bundle_root
  collect_root_deps
  resolve_apt_closure
  download_apt_debs
  assert_environment_debs
  write_apt_repo_index
  write_offline_installer
  validate_offline_dependencies
  write_readme
  make_tarball
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
