import importlib.util
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).resolve().parents[1] / 'builder/package/prune_business_packages.py'
spec = importlib.util.spec_from_file_location('prune', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PruneTest(unittest.TestCase):
    def test_only_named_package_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            removed = ['share/navi_robot_msgs/package.xml',
                       'lib/libnavi_robot_msgs__rosidl_typesupport_cpp.so',
                       'share/ament_index/resource_index/packages/navi_robot_msgs',
                       'lib/python3.8/site-packages/navi_robot_msgs/__init__.py']
            preserved = ['share/robot_state_publisher/package.xml', 'lib/librclcpp.so']
            for name in removed + preserved:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            module.prune(root, ['navi_robot_msgs'])
            self.assertTrue(all(not (root / name).exists() for name in removed))
            self.assertTrue(all((root / name).exists() for name in preserved))

    def test_rejects_live_prefix(self):
        with self.assertRaises(ValueError):
            module.prune('/opt/ros/humble', ['navi_robot_msgs'])

    def test_rejects_path_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                module.prune(directory, ['../etc'])

    def test_rejects_business_overlay(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            index = root / 'share/ament_index/resource_index/packages'
            index.mkdir(parents=True)
            (index / 'rclcpp').touch()
            allowed = root / 'allowed.txt'
            allowed.write_text('rclcpp\n')
            module.validate_environment(root, allowed)
            (index / 'naviai_robot').touch()
            with self.assertRaisesRegex(ValueError, 'naviai_robot'):
                module.validate_environment(root, allowed)


if __name__ == '__main__':
    unittest.main()
