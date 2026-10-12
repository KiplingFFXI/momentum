"""Check archive contents and reject unsafe or accidental release inputs."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_release', ROOT / 'tools/build_release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='momentum_package_test_')
        self.folder = Path(self.work.name)
        self.addon = self.folder / 'momentum'
        shutil.copytree(ROOT / 'momentum', self.addon)

    def tearDown(self):
        self.work.cleanup()

    def test_reproducible_archive_and_manifest(self):
        first, count, digest = release.build(self.folder / 'one', self.addon)
        second, _, second_digest = release.build(self.folder / 'two', self.addon)
        self.assertEqual(digest, second_digest)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with zipfile.ZipFile(first) as archive:
            self.assertEqual(count, len(release.FILES) + len(release.SOUNDS) + 1)
            self.assertEqual(set(archive.namelist()), {'momentum/LICENSE'} | {'momentum/' + name for name in release.FILES | release.SOUNDS.keys()})
            self.assertIsNone(archive.testzip())
            for member in archive.infolist():
                self.assertEqual(member.date_time, (1980, 1, 1, 0, 0, 0))

    def test_extra_runtime_file_is_rejected(self):
        (self.addon / 'settings.json').write_text('{}', encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'Unexpected'):
            release.addon_files(self.addon)

    def test_cli_custom_output_directory(self):
        import subprocess
        import sys
        output = self.folder / 'ci-artifacts'
        result = subprocess.run([sys.executable, str(ROOT / 'tools/build_release.py'), '--out', str(output)],
                                text=True, capture_output=True, check=True)
        self.assertIn('SHA-256 ', result.stdout)
        self.assertTrue((output / ('momentum-%s.zip' % release.addon_version())).is_file())

    def test_missing_runtime_file_is_rejected(self):
        (self.addon / 'core/tracker.lua').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Missing'):
            release.addon_files(self.addon)

    def test_private_path_is_rejected(self):
        (self.addon / 'core/tracker.lua').write_text('-- C:/' + 'Users/Example/private.txt', encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'Private path'):
            release.build(self.folder / 'out', self.addon)

    def test_embedded_output_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'outside'):
            release.build(self.addon / 'out', self.addon)

    def test_changed_sound_asset_is_rejected(self):
        (self.addon / 'sounds/FF VII Save.mp3').write_bytes(b'not the verified sound file')
        with self.assertRaisesRegex(RuntimeError, 'hash mismatch'):
            release.build(self.folder / 'out', self.addon)

    def test_changed_version_names_archive(self):
        entry = self.addon / 'momentum.lua'
        current = release.addon_version(self.addon)
        entry.write_text(entry.read_text(encoding='ascii').replace("addon.version = '%s';" % current, "addon.version = '9.8.7';"), encoding='ascii')
        path, _, _ = release.build(self.folder / 'out', self.addon)
        self.assertEqual(path.name, 'momentum-9.8.7.zip')

    def test_server_companion_is_separate_and_reproducible(self):
        first, count, digest = release.build_server(self.folder / 'one')
        second, _, second_digest = release.build_server(self.folder / 'two')
        self.assertEqual(digest, second_digest)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with zipfile.ZipFile(first) as archive:
            self.assertEqual(count, 4)
            self.assertEqual(set(archive.namelist()), {
                'momentum-status-server/README.txt',
                'momentum-status-server/momentum_status.lua',
                'momentum-status-server/momentum_chain.cpp',
                'momentum-status-server/LICENSE',
            })
            self.assertIsNone(archive.testzip())

    def test_server_extra_file_is_rejected(self):
        server = self.folder / 'server'
        shutil.copytree(ROOT / 'server', server)
        (server / 'settings.json').write_text('{}', encoding='ascii')
        with self.assertRaisesRegex(RuntimeError, 'Unexpected'):
            release.build_server(self.folder / 'out', server)


if __name__ == '__main__':
    unittest.main(verbosity=2)
