"""Check archive contents and reject unsafe or accidental release inputs."""
import importlib.util
from pathlib import Path
import shutil
import struct
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

    def test_sound_helper_bytes_are_preserved_in_archive(self):
        path, _, _ = release.build(self.folder / 'out', self.addon)
        with zipfile.ZipFile(path) as archive:
            for name in release.NATIVE:
                self.assertEqual(archive.read('momentum/' + name), (self.addon / name).read_bytes())

    def test_missing_sound_helper_is_rejected(self):
        for name in release.NATIVE:
            path = self.addon / name
            original = path.read_bytes()
            path.unlink()
            with self.assertRaisesRegex(RuntimeError, 'Missing'):
                release.build(self.folder / 'out', self.addon)
            path.write_bytes(original)

    def test_unreviewed_executable_is_rejected(self):
        for suffix in ('.exe', '.dll'):
            path = self.addon / ('bin/other' + suffix)
            path.write_bytes((self.addon / release.HELPER).read_bytes())
            with self.assertRaisesRegex(RuntimeError, 'Unexpected'):
                release.addon_files(self.addon)
            with self.assertRaisesRegex(RuntimeError, 'Unexpected native binary'):
                release.checked_bytes(path, 'momentum/bin/other' + suffix)
            path.unlink()

    def test_invalid_or_wrong_machine_sound_helper_is_rejected(self):
        for name in release.NATIVE:
            path = self.addon / name
            original = path.read_bytes()
            path.write_bytes(b'not an executable')
            with self.assertRaisesRegex(RuntimeError, 'PE executable'):
                release.checked_bytes(path, 'momentum/' + name)
            offset = struct.unpack_from('<I', original, 0x3C)[0]
            wrong_machine = bytearray(original)
            struct.pack_into('<H', wrong_machine, offset + 4, 0x8664)
            path.write_bytes(wrong_machine)
            with self.assertRaisesRegex(RuntimeError, '32-bit x86'):
                release.checked_bytes(path, 'momentum/' + name)
            wrong_kind = bytearray(original)
            flags = struct.unpack_from('<H', original, offset + 22)[0]
            struct.pack_into('<H', wrong_kind, offset + 22, flags ^ 0x2000)
            path.write_bytes(wrong_kind)
            with self.assertRaisesRegex(RuntimeError, '32-bit x86'):
                release.checked_bytes(path, 'momentum/' + name)

    def test_sound_helper_subsystem_and_section_bounds_are_checked(self):
        for name in release.NATIVE:
            path = self.addon / name
            original = path.read_bytes()
            offset = struct.unpack_from('<I', original, 0x3C)[0]
            console = bytearray(original)
            struct.pack_into('<H', console, offset + 24 + 68, 3)
            path.write_bytes(console)
            with self.assertRaisesRegex(RuntimeError, 'Windows subsystem'):
                release.checked_bytes(path, 'momentum/' + name)
            bad_section = bytearray(original)
            optional_size = struct.unpack_from('<H', original, offset + 20)[0]
            struct.pack_into('<I', bad_section, offset + 24 + optional_size + 20, len(original) + 1)
            path.write_bytes(bad_section)
            with self.assertRaisesRegex(RuntimeError, 'section range'):
                release.checked_bytes(path, 'momentum/' + name)

    def test_sound_helper_private_paths_are_rejected_in_plain_and_wide_text(self):
        value = 'C:/' + 'Users/Example/private.pdb'
        for name in release.NATIVE:
            path = self.addon / name
            original = path.read_bytes()
            for encoding in ('ascii', 'utf-16-le', 'utf-16-be'):
                for padding in (b'', b'x'):
                    with self.subTest(name=name, encoding=encoding, padding=padding):
                        path.write_bytes(original + padding + value.encode(encoding))
                        with self.assertRaisesRegex(RuntimeError, 'Private path'):
                            release.checked_bytes(path, 'momentum/' + name)

    def test_stale_or_missing_sound_helper_source_marker_is_rejected(self):
        for name, (_, marker, _) in release.NATIVE.items():
            path = self.addon / name
            original = path.read_bytes()
            offset = original.index(marker) + len(marker)
            stale = bytearray(original)
            stale[offset] = ord('0') if original[offset] != ord('0') else ord('1')
            for data in (bytes(stale), original.replace(marker, b'x' * len(marker), 1), original + marker + b'invalid'):
                path.write_bytes(data)
                with self.assertRaisesRegex(RuntimeError, 'stale|source marker'):
                    release.checked_bytes(path, 'momentum/' + name)

    def test_changed_native_source_requires_a_new_sound_helper(self):
        for name, (script, _, _) in release.NATIVE.items():
            source_root = self.folder / Path(script).stem
            source_name = 'native/' + ('sound_launcher.cpp' if name == release.LAUNCHER else 'sound_player.cpp')
            for relative in (source_name, script):
                target = source_root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            path = self.addon / name
            self.assertEqual(release.checked_bytes(path, 'momentum/' + name, source_root), path.read_bytes())
            source = source_root / source_name
            source.write_bytes(source.read_bytes() + b'\n// A source change needs a fresh binary.\n')
            with self.assertRaisesRegex(RuntimeError, 'stale|source marker'):
                release.checked_bytes(path, 'momentum/' + name, source_root)

    def test_launcher_with_test_hooks_cannot_be_packaged(self):
        path = self.addon / release.LAUNCHER
        path.write_bytes(path.read_bytes() + release.LAUNCHER_TEST_MARKER)
        with self.assertRaisesRegex(RuntimeError, 'Test launcher'):
            release.build(self.folder / 'out', self.addon)

    def test_changed_version_names_archive(self):
        entry = self.addon / 'momentum.lua'
        current = release.addon_version(self.addon)
        entry.write_text(entry.read_text(encoding='ascii').replace("addon.version = '%s';" % current, "addon.version = '9.8.7';"), encoding='ascii')
        path, _, _ = release.build(self.folder / 'out', self.addon)
        self.assertEqual(path.name, 'momentum-9.8.7.zip')

if __name__ == '__main__':
    unittest.main(verbosity=2)
