#!/usr/bin/env python3
"""Remove named ROS overlay packages from a staged base environment only."""
import argparse
from pathlib import Path
import re
import shutil


def prune(prefix, packages):
    prefix = Path(prefix)
    if prefix.resolve() == Path('/opt/ros/humble'):
        raise ValueError('Refusing to modify the live ROS environment')
    for package in packages:
        if not re.fullmatch(r'[a-z][a-z0-9_]*', package):
            raise ValueError('Invalid ROS package name: ' + package)
    removed = []
    for package in packages:
        patterns = [
            'share/' + package, 'include/' + package, 'lib/' + package,
            'lib/lib' + package + '*.so*', 'lib/pkgconfig/' + package + '.pc',
            'share/ament_index/resource_index/*/' + package,
            'lib/python*/site-packages/' + package,
            'lib/python*/site-packages/' + package + '-*.egg-info',
            'lib/python*/site-packages/' + package + '-*.dist-info',
        ]
        for pattern in patterns:
            for path in prefix.glob(pattern):
                removed.append(str(path.relative_to(prefix)))
                if path.is_symlink() or path.is_file():
                    path.unlink()
                elif path.is_dir():
                    shutil.rmtree(path)
    return removed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix')
    parser.add_argument('packages', nargs='+')
    args = parser.parse_args()
    for removed in prune(args.prefix, args.packages):
        print(removed)
