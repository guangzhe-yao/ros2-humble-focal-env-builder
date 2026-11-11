import importlib.util
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).resolve().parents[1] / 'builder/package/validate_environment.py'
spec = importlib.util.spec_from_file_location('boundary', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BoundaryTest(unittest.TestCase):
    def test_unindexed_vendor_payload_is_rejected_and_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'share/ament_index/resource_index/packages').mkdir(parents=True)
            residue = root / 'lib/python3.8/site-packages/zj_humanoid/navi_robot_msgs/file.py'
            residue.parent.mkdir(parents=True)
            residue.touch()
            allowed = root / 'allowed.txt'
            allowed.write_text('rclcpp\n')
            excluded = root / 'excluded.txt'
            excluded.write_text('zj_humanoid\n')
            with self.assertRaisesRegex(ValueError, 'outside ROS index'):
                module.validate_environment(root, allowed, excluded=excluded)
            self.assertTrue(residue.exists())

    def test_business_overlay_is_rejected_without_deleting_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            index = root / 'share/ament_index/resource_index/packages'
            index.mkdir(parents=True)
            (index / 'navi_robot_msgs').touch()
            allowed = root / 'allowed.txt'
            allowed.write_text('rclcpp\n')
            with self.assertRaisesRegex(ValueError, 'navi_robot_msgs'):
                module.validate_environment(root, allowed)
            self.assertTrue((index / 'navi_robot_msgs').exists())

    def test_required_packages_and_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            index = root / 'share/ament_index/resource_index/packages'
            index.mkdir(parents=True)
            (index / 'rclcpp').touch()
            package = root / 'share/rclcpp'
            package.mkdir()
            (package / 'package.xml').write_text('<package><name>rclcpp</name><version>1.0</version></package>')
            allowed = root / 'allowed.txt'
            allowed.write_text('rclcpp\njoy_teleop\n')
            module.validate_environment(root, allowed)
            required = root / 'required.txt'
            required.write_text('# runtime\njoy_teleop\n')
            with self.assertRaisesRegex(ValueError, 'joy_teleop'):
                module.validate_environment(root, allowed, required)
            (package / 'package.xml').write_text('<package><name>wrong</name></package>')
            with self.assertRaisesRegex(ValueError, 'Invalid package metadata'):
                module.validate_environment(root, allowed)
