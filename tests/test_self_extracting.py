import importlib.util
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('self_extracting', ROOT / 'builder/package/build_self_extracting.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SelfExtractingTest(unittest.TestCase):
    def archive(self, root, bad=None):
        archive = root / 'fixture.tar.gz'
        with tarfile.open(archive, 'w:gz') as bundle:
            content = b'#!/bin/bash\nprintf installed > "$RESULT"\n'
            member = tarfile.TarInfo('fixture/install.sh')
            member.size = len(content)
            bundle.addfile(member, io.BytesIO(content))
            if bad:
                bundle.addfile(bad)
        return archive

    def test_execution_checksum_and_no_overwrite(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = self.archive(root)
            run = root / 'installer.run'
            module.build(archive, run)
            result = root / 'result'
            env = dict(os.environ, RESULT=str(result))
            subprocess.run(['bash', str(run)], env=env, check=True, stdout=subprocess.PIPE)
            self.assertEqual(result.read_text(), 'installed')
            with self.assertRaises(FileExistsError):
                module.build(archive, run)
            result.unlink()
            with run.open('ab') as output:
                output.write(b'corrupt')
            check = subprocess.run(['bash', str(run)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(check.returncode, 0)
            self.assertFalse(result.exists())

    def test_unsafe_archive_members_are_rejected(self):
        for kind in ('parent', 'absolute', 'symlink', 'second_root'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                names = {'parent': 'fixture/../../escape', 'absolute': '/escape',
                         'symlink': 'fixture/link', 'second_root': 'second/file'}
                member = tarfile.TarInfo(names[kind])
                if kind == 'symlink':
                    member.type = tarfile.SYMTYPE
                    member.linkname = '/etc'
                archive = self.archive(root, member)
                with self.assertRaises(ValueError):
                    module.build(archive, root / 'installer.run')
                self.assertFalse((root / 'installer.run').exists())
