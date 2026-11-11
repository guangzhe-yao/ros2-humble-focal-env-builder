import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audit', ROOT / 'builder/audit_project_dependencies.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ProfileTest(unittest.TestCase):
    def test_required_packages_are_in_release_and_registry(self):
        required = audit.names(ROOT / 'profiles/pico-ros-packages.txt')
        self.assertLessEqual(required, audit.names(ROOT / 'profiles/humble-environment-packages.txt'))
        upstream = json.loads((ROOT / 'profiles/ros-upstream.json').read_text())['packages']
        self.assertLessEqual(required, upstream.keys())

    def test_local_package_wins_over_upstream_name_and_launch_is_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'package.xml').write_text('<package><name>joy</name><depend>joy</depend><depend>roscpp</depend><depend>rtipc_runtime</depend></package>')
            (root / 'example.launch').write_text('<launch><node pkg="joy_teleop" type="joy_teleop"/><!-- <node pkg="unused"/> --></launch>')
            report = audit.audit([root], {'joy': {}, 'joy_teleop': {}},
                                 {'roscpp': {'ros2': ['rclcpp']}}, set())
            rows = {row['name']: row for row in report['dependencies']}
            self.assertEqual(rows['joy']['category'], 'local_or_vendored')
            self.assertFalse(rows['joy_teleop']['included'])
            self.assertEqual(rows['roscpp']['ros2'], ['rclcpp'])
            self.assertEqual(rows['rtipc_runtime']['category'], 'system_vendor_or_unresolved')
            self.assertNotIn('unused', rows)

    def test_python_launch_literal_and_missing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'example.launch.py').write_text("Node(package='joy_teleop'); FindPackageShare('xacro')")
            report = audit.audit([root], {'joy_teleop': {}, 'xacro': {}}, {}, {'xacro'})
            self.assertEqual(len(report['dependencies']), 2)
            with self.assertRaises(ValueError):
                audit.audit([root / 'missing'], {}, {}, set())
