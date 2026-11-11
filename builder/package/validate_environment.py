#!/usr/bin/env python3
"""Validate a clean upstream ROS prefix without modifying or pruning it."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET


def validate_environment(prefix, allowlist, required=None, excluded=None):
    allowed = set(Path(allowlist).read_text().splitlines())
    index = Path(prefix) / 'share/ament_index/resource_index/packages'
    actual = {path.name for path in index.iterdir()}
    unexpected = sorted(actual - allowed)
    if unexpected:
        raise ValueError('Use a clean Humble prefix; unexpected overlay packages: '
                         + ', '.join(unexpected))
    if excluded:
        forbidden = {line.split('#', 1)[0].strip() for line in Path(excluded).read_text().splitlines()} - {''}
        for path in Path(prefix).rglob('*'):
            relative = path.relative_to(prefix)
            if forbidden.intersection(relative.parts) or any(
                    path.name.startswith('lib' + name + '__') for name in forbidden):
                raise ValueError('Business/vendor payload outside ROS index: ' + str(relative))
    if required:
        needed = {line.split('#', 1)[0].strip() for line in Path(required).read_text().splitlines()} - {''}
        missing = sorted(needed - actual)
        if missing:
            raise ValueError('Missing required Pico ROS packages: ' + ', '.join(missing))
    for name in actual:
        manifest = Path(prefix) / 'share' / name / 'package.xml'
        xml = ET.parse(manifest).getroot()
        if xml.findtext('name') != name or not xml.findtext('version'):
            raise ValueError('Invalid package metadata: ' + str(manifest))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix')
    parser.add_argument('--allowlist', required=True)
    parser.add_argument('--required')
    parser.add_argument('--excluded')
    args = parser.parse_args()
    validate_environment(args.prefix, args.allowlist, args.required, args.excluded)
