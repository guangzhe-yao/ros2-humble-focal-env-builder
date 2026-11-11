import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('inventory', ROOT / 'builder/package/write_inventory.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class InventoryTest(unittest.TestCase):
    def test_actual_metadata_hashes_and_honest_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'apt_debs').mkdir()
            (root / 'apt_debs/example.deb').write_bytes(b'test archive')
            (root / 'root-packages.txt').write_text('example=2.0\n')
            (root / 'ros-packages.txt').write_text('rclcpp\n')
            with patch.object(module.subprocess, 'check_output', return_value='Package: example\nVersion: 2.0\nArchitecture: amd64\nDepends: first (>= 1) |\n second\nPre-Depends: setup\n'):
                result = module.inventory(root)
                self.assertEqual(result['deb_count'], 1)
                self.assertEqual(result['debs'][0]['version'], '2.0')
                self.assertIn('first (>= 1) |', result['debs'][0]['depends'])
                self.assertIn('second', result['debs'][0]['depends'])
                self.assertEqual(result['debs'][0]['pre_depends'], 'setup')
                self.assertEqual(len(result['debs'][0]['sha256']), 64)
                self.assertEqual(result['source_provenance']['status'], 'unverified')
                (root / 'artifacts').mkdir()
                (root / 'artifacts/build-provenance.json').write_text(json.dumps({'status': 'partial'}))
                self.assertEqual(module.inventory(root)['source_provenance']['status'], 'partial')
