#!/usr/bin/env python3
"""Read local Pico sources without building them or treating local packages as upstream."""
import argparse
import ast
from collections import defaultdict
import json
import os
from pathlib import Path
import re
import xml.etree.ElementTree as ET

PROFILES = Path(__file__).resolve().parents[1] / 'profiles'
SKIP = {'.git', 'build', 'devel', 'install', 'install_deploy', 'log', 'node_modules', '__pycache__'}


def names(path):
    return {line.split('#', 1)[0].strip() for line in path.read_text().splitlines()} - {''}


def audit(roots, upstream, migrations, included):
    local = defaultdict(list)
    dependencies = defaultdict(list)
    warnings = []
    files = []
    for root in roots:
        if not root.is_dir():
            raise ValueError('Missing project directory: ' + str(root))
        for directory, children, entries in os.walk(root):
            children[:] = sorted(child for child in children if child not in SKIP)
            for entry in sorted(entries):
                path = Path(directory) / entry
                if entry == 'package.xml':
                    xml = ET.parse(path).getroot()
                    name = xml.findtext('name')
                    if not name:
                        raise ValueError('Missing package name: ' + str(path))
                    local[name.strip()].append(str(path))
                    for node in xml:
                        if node.tag.endswith('depend') and node.text:
                            dependencies[node.text.strip()].append(str(path))
                elif entry == 'CMakeLists.txt' or entry.endswith(('.launch', '.launch.xml', '.launch.py')):
                    files.append(path)
    for path in files:
        source = path.read_text()
        found = set()
        if path.name == 'CMakeLists.txt':
            # Only literal find_package names; this is not a CMake evaluator.
            source = re.sub(r'#[^\n]*', '', source)
            found.update(re.findall(r'\bfind_package\s*\(\s*([A-Za-z0-9_-]+)', source))
        elif path.suffix == '.py':
            try:
                tree = ast.parse(source)
            except SyntaxError as error:
                warnings.append(str(path) + ': ' + str(error))
                continue
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                for keyword in node.keywords:
                    if keyword.arg == 'package' and isinstance(keyword.value, ast.Constant) and isinstance(keyword.value.value, str):
                        found.add(keyword.value.value)
                function = getattr(node.func, 'id', getattr(node.func, 'attr', ''))
                if function in {'get_package_share_directory', 'get_package_prefix', 'FindPackageShare'} and node.args:
                    arg = node.args[0]
                    if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                        found.add(arg.value)
        else:
            try:
                tree = ET.fromstring(source)
            except ET.ParseError as error:
                warnings.append(str(path) + ': ' + str(error))
                continue
            for node in tree.iter():
                if node.get('pkg'):
                    found.add(node.get('pkg'))
                for value in node.attrib.values():
                    found.update(re.findall(r'\$\(find(?:-pkg-share)?\s+([a-zA-Z0-9_]+)\)', value))
        for name in found:
            dependencies[name].append(str(path))
    result = []
    for name, evidence in sorted(dependencies.items()):
        row = {'name': name, 'evidence': sorted(set(evidence))}
        if name in local:
            row.update(category='local_or_vendored', declarations=local[name])
        elif name in migrations:
            row.update(category='ros1_migration', **migrations[name])
        elif name in upstream:
            row.update(category='upstream_ros2', included=name in included, **upstream[name])
        elif name == 'ament_python':
            row.update(category='build_type', note='Provided by the colcon/ament Python build tooling, not a ROS resource package.')
        else:
            row.update(category='system_vendor_or_unresolved')
        result.append(row)
    return {'schema_version': 1, 'scope': [str(root) for root in roots],
            'local_packages': dict(sorted(local.items())), 'dependencies': result,
            'warnings': warnings,
            'limitations': ['Static declarations and literal launch/CMake references only; conditions are not evaluated.',
                            'Local/vendored packages are never automatically approved as upstream.',
                            'Unknown names require review; this report is not an installation list.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('roots', type=Path, nargs='+')
    args = parser.parse_args()
    catalog = json.loads((PROFILES / 'ros-upstream.json').read_text())
    migrations = json.loads((PROFILES / 'ros1-migration.json').read_text())
    report = audit(args.roots, catalog['packages'], migrations,
                   names(PROFILES / 'humble-environment-packages.txt'))
    report['upstream_registry'] = {key: value for key, value in catalog.items() if key != 'packages'}
    print(json.dumps(report, indent=2, ensure_ascii=False))
