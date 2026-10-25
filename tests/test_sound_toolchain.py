"""Check SDK discovery without an installed compiler or Windows SDK."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load_builder(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / ('tools/' + name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BUILDERS = {name: load_builder('build_sound_' + name) for name in ('launcher', 'player')}


class SoundToolchainTests(unittest.TestCase):
    def discover(self, name, folder, directories=None, files=(), architecture='x86'):
        programs = Path(folder) / 'Program Files'
        visual_studio = Path(folder) / 'Visual Studio'
        (visual_studio / 'VC/Tools/MSVC/14.51.36231').mkdir(parents=True)
        include = programs / 'Windows Kits/10/Include'
        if directories is not None:
            include.mkdir(parents=True)
            for directory in directories:
                (include / directory).mkdir()
        for file in files:
            (include / file).touch()
        builder = BUILDERS[name]
        with mock.patch.dict(os.environ, {'ProgramFiles(x86)': str(programs)}), \
                mock.patch.object(builder.subprocess, 'check_output', return_value=str(visual_studio) + '\n'):
            return builder.toolchain(architecture) if name == 'launcher' else builder.toolchain()

    def test_driver_and_nonversion_folders_do_not_hide_the_newest_sdk(self):
        directories = ('wdf', 'um', '10.0', '10.0.22621', '10.0.22621.0-preview',
                       '10.0.invalid.0', '10.0.9999.0', '10.0.10000.0')
        for name in BUILDERS:
            with self.subTest(builder=name), tempfile.TemporaryDirectory(prefix='momentum_sdk_') as folder:
                binary, environment = self.discover(name, folder, directories, files=('10.0.99999.0',))
                root = Path(folder)
                sdk = root / 'Program Files/Windows Kits/10/Include/10.0.10000.0'
                includes = environment['INCLUDE'].split(';')
                self.assertEqual(includes[-3:], [str(sdk / part) for part in ('ucrt', 'shared', 'um')])
                self.assertNotIn('wdf', environment['INCLUDE'])
                self.assertIn(str(root / 'Program Files/Windows Kits/10/Lib/10.0.10000.0/um/x86'),
                              environment['LIB'].split(';'))
                self.assertIn('Hostx64', str(binary))

    def test_nonversion_only_sdk_directory_has_a_clear_error(self):
        for name in BUILDERS:
            with self.subTest(builder=name), tempfile.TemporaryDirectory(prefix='momentum_sdk_') as folder:
                with self.assertRaisesRegex(RuntimeError, 'Windows SDK.*four-part version'):
                    self.discover(name, folder, ('wdf', '10.0.22621', '10.0.22621.0-preview'))

    def test_missing_and_empty_sdk_include_directory_have_a_clear_error(self):
        for name in BUILDERS:
            for directories in (None, ()):
                with self.subTest(builder=name, directories=directories), \
                        tempfile.TemporaryDirectory(prefix='momentum_sdk_') as folder:
                    with self.assertRaisesRegex(RuntimeError, 'Windows SDK.*four-part version'):
                        self.discover(name, folder, directories)

    def test_launcher_keeps_the_requested_architecture(self):
        with tempfile.TemporaryDirectory(prefix='momentum_sdk_') as folder:
            binary, environment = self.discover('launcher', folder, ('wdf', '10.0.26100.0'), architecture='x64')
            self.assertEqual(binary.name, 'x64')
            self.assertTrue(all(Path(part).name == 'x64' for part in environment['LIB'].split(';')))


if __name__ == '__main__':
    unittest.main()
