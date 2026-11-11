#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
source "$REPO/deploy/pico/install_humble_environment.sh"
ROOT="$temp"
mkdir -p "$temp/db/updates" "$temp/repo" "$temp/lists/partial" "$temp/parts" "$temp/pkg/DEBIAN"
printf 'Package: unit-system-lib\nStatus: install ok installed\nVersion: 1\nArchitecture: amd64\nMaintainer: Test <test@example.com>\nDescription: installed library\n\nPackage: unit-host-app\nStatus: install ok installed\nVersion: 1\nArchitecture: amd64\nMaintainer: Test <test@example.com>\nDepends: unit-system-lib (= 1)\nDescription: installed host application\n' > "$temp/db/status"
dpkg-query() { command dpkg-query --admindir="$temp/db" "$@"; }
[[ "$(dpkg-query -W -f='${db:Status-Status} ${Version}' unit-system-lib)" == 'installed 1' ]]
make_deb() {
  printf 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: Test <test@example.com>\nDescription: fixture\n' "$1" "$2" > "$temp/pkg/DEBIAN/control"
  [[ -z "${3:-}" ]] || printf 'Depends: %s\n' "$3" >> "$temp/pkg/DEBIAN/control"
  dpkg-deb --build --root-owner-group "$temp/pkg" "$temp/repo/${1}_${2}_amd64.deb" >/dev/null
}
make_deb unit-system-lib 2
make_deb ros2-humble-focal-desktop-source 2 'unit-system-lib (>= 1)'
make_deb unit-new-tool 1
(cd "$temp/repo"; dpkg-scanpackages . /dev/null > Packages)
printf 'deb [trusted=yes] file:%s ./\n' "$temp/repo" > "$temp/sources.list"
opts=(-o "Dir::Etc::sourcelist=$temp/sources.list" -o "Dir::Etc::sourceparts=$temp/parts"
      -o "Dir::State::Lists=$temp/lists" -o "Dir::State::status=$temp/db/status"
      -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache=
      -o "APT::Sandbox::User=$(id -un)" -o Acquire::Languages=none)
apt-get "${opts[@]}" update > "$temp/update.log" 2>&1
printf 'unit-system-lib\nunit-new-tool\nros2-humble-focal-desktop-source=2\n' > "$ROOT/root-packages.txt"
mapfile -t roots < <(installation_roots)
[[ ${#roots[@]} -eq 2 ]]
[[ "${roots[0]}" == unit-new-tool ]]
[[ "${roots[1]}" == ros2-humble-focal-desktop-source=2 ]]
# The old request attempts to replace a library and remove a dependent host app.
if apt-get "${opts[@]}" -s --no-remove install unit-system-lib ros2-humble-focal-desktop-source=2 > "$temp/unsafe.log" 2>&1; then
  echo 'Fixture failed to expose the unsafe system upgrade' >&2; exit 1
fi
apt-get "${opts[@]}" -s --no-remove --no-install-recommends install "${roots[@]}" > "$temp/safe.log"
! grep -Eq '^(Remv |Inst unit-system-lib )' "$temp/safe.log"
grep -q '^Inst ros2-humble-focal-desktop-source ' "$temp/safe.log"
grep -q '^Inst unit-new-tool ' "$temp/safe.log"
# A real newer-library requirement must not remove the dependent host app.
make_deb ros2-humble-focal-desktop-source 3 'unit-system-lib (>= 2)'
(cd "$temp/repo"; dpkg-scanpackages --multiversion . /dev/null > Packages)
apt-get "${opts[@]}" update > "$temp/update.log" 2>&1
printf 'unit-system-lib\nros2-humble-focal-desktop-source=3\n' > "$ROOT/root-packages.txt"
mapfile -t roots < <(installation_roots)
if apt-get "${opts[@]}" -s --no-remove install "${roots[@]}" > "$temp/conflict.log" 2>&1; then
  echo 'Incompatible system dependency was accepted' >&2; exit 1
fi
# A clean base without that host app must permit a required library upgrade.
sed '/^Package: unit-host-app/,$d' "$temp/db/status" > "$temp/db/status.new"
mv "$temp/db/status.new" "$temp/db/status"
apt-get "${opts[@]}" -s --no-remove install "${roots[@]}" > "$temp/required-upgrade.log"
grep -q '^Inst unit-system-lib ' "$temp/required-upgrade.log"
echo 'Unnecessary system upgrades are avoided; required upgrades resolve without host removals.'
