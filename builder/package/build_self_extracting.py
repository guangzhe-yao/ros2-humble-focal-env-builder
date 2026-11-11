#!/usr/bin/env python3
"""Wrap a validated offline bundle in a single self-extracting Bash installer."""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import shutil
import tarfile


def bundle_root(archive):
    roots = set()
    installers = set()
    with tarfile.open(archive, 'r:gz') as bundle:
        for member in bundle:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts:
                raise ValueError('Unsafe archive path: ' + member.name)
            if not (member.isfile() or member.isdir()):
                raise ValueError('Only regular files and directories are allowed: ' + member.name)
            roots.add(path.parts[0])
            if len(path.parts) == 2 and path.name == 'install.sh' and member.isfile():
                installers.add(path.parts[0])
    if len(roots) != 1 or roots != installers:
        raise ValueError('Expected one bundle directory containing install.sh')
    root = roots.pop()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*', root):
        raise ValueError('Invalid bundle directory name')
    return root


def build(archive, destination):
    root = bundle_root(archive)
    digest = hashlib.sha256()
    with archive.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    header = '''#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 0 ]] || { echo "Usage: sudo bash $0" >&2; exit 64; }
umask 077
self="$(readlink -f "${BASH_SOURCE[0]}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo 'Checking offline Pico environment payload...'
tail -n +@LINE@ "$self" > "$work/payload.tar.gz"
printf '%s  %s\n' '@SHA256@' "$work/payload.tar.gz" | sha256sum -c -
tar --no-same-owner --no-same-permissions -xzf "$work/payload.tar.gz" -C "$work"
bash "$work/@ROOT@/install.sh"
exit 0
# __PICO_OFFLINE_PAYLOAD__
'''
    header = header.replace('@ROOT@', root).replace('@SHA256@', digest.hexdigest())
    header = header.replace('@LINE@', str(header.count('\n') + 1))
    # Exclusive creation preserves existing versioned installers.
    with destination.open('xb') as output, archive.open('rb') as payload:
        output.write(header.encode('ascii'))
        shutil.copyfileobj(payload, output)
    destination.chmod(0o755)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    build(args.archive, args.destination)
