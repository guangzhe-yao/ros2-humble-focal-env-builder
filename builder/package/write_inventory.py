#!/usr/bin/env python3
"""Record actual offline DEB metadata and hashes; never infer source provenance."""
import argparse
from email.parser import Parser
import hashlib
import json
from pathlib import Path
import subprocess


def inventory(root):
    packages = []
    for path in sorted((root / 'apt_debs').glob('*.deb')):
        fields = subprocess.check_output(['dpkg-deb', '-f', str(path)], text=True)
        metadata = Parser().parsestr(fields)
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        packages.append(dict(name=metadata['Package'], version=metadata['Version'],
                             architecture=metadata['Architecture'],
                             depends=metadata.get('Depends', ''),
                             pre_depends=metadata.get('Pre-Depends', ''),
                             file=str(path.relative_to(root)), bytes=path.stat().st_size,
                             sha256=digest.hexdigest()))
    provenance = root / 'artifacts/build-provenance.json'
    return {
        'schema_version': 1,
        'target': {'ubuntu': '20.04', 'architecture': 'amd64', 'ros': 'humble'},
        'source_provenance': json.loads(provenance.read_text()) if provenance.exists()
        else {'status': 'unverified', 'note': 'A repos configuration is not proof of the binary build.'},
        'apt_roots': (root / 'root-packages.txt').read_text().splitlines(),
        'ros_packages': (root / 'ros-packages.txt').read_text().splitlines(),
        'deb_count': len(packages), 'debs': packages,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    args = parser.parse_args()
    print(json.dumps(inventory(args.bundle), indent=2, sort_keys=True))
