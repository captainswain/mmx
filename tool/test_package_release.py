"""Artifact content and deterministic-container checks; no builds required."""
import hashlib
import os
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
import tarfile

spec = importlib.util.spec_from_file_location('package_release', Path(__file__).with_name('package_release.py'))
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class PackageTests(unittest.TestCase):
    def test_portable_is_repeatable_and_preserves_executable(self):
        for system in ('linux', 'windows'):
            with self.subTest(system=system), tempfile.TemporaryDirectory() as scratch:
                directory = Path(scratch)
                stage = directory / 'mmx-test'
                stage.mkdir()
                executable = stage / 'mmx'
                executable.write_bytes(b'example binary')
                executable.chmod(0o755)
                (stage / 'LICENSE').write_text('license\n')
                first = packaging.portable(stage, directory / 'first', system, 1700000000)
                second = packaging.portable(stage, directory / 'second', system, 1700000000)
                self.assertEqual(packaging.digest_file(first), packaging.digest_file(second))
                if system == 'linux':
                    with tarfile.open(first) as archive:
                        if os.name != 'nt':
                            self.assertEqual(archive.getmember('mmx-test/mmx').mode, 0o755)
                        self.assertEqual(archive.extractfile('mmx-test/mmx').read(), b'example binary')
                else:
                    with zipfile.ZipFile(first) as archive:
                        self.assertEqual(archive.read('mmx-test/mmx'), b'example binary')
                self.assertTrue(first.with_name(first.name + '.sha256').is_file())

    def test_manifest_records_content_and_links(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            (root / 'a').write_bytes(b'abc')
            self.assertEqual(packaging.tree_manifest(root)['a']['sha256'], hashlib.sha256(b'abc').hexdigest())

    def test_installed_manifest_detects_corruption_and_unsafe_paths(self):
        with tempfile.TemporaryDirectory(prefix='mmx package ') as scratch:
            root = Path(scratch)
            payload = root / 'binary'
            payload.write_bytes(b'original executable')
            manifest = root / 'provenance.json'
            data = {'files': packaging.tree_manifest(root)}
            manifest.write_text(json.dumps(data), encoding='utf-8')
            command = [sys.executable, str(Path(__file__).with_name('verify_manifest.py')),
                       str(manifest), '--root', str(root)]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            payload.write_bytes(b'corrupt executable!')
            corrupt = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(corrupt.returncode, 0)
            self.assertIn('Content mismatch', corrupt.stderr)
            data['files'] = {'../outside': {'sha256': '0' * 64, 'size': 0}}
            manifest.write_text(json.dumps(data), encoding='utf-8')
            unsafe = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(unsafe.returncode, 0)
            self.assertIn('Invalid manifest path', unsafe.stderr)


if __name__ == '__main__':
    unittest.main()
