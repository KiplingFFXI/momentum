"""Exercise explicit sound preservation with the real Windows copy API."""
import os
from pathlib import Path
import tempfile
import unittest

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'nt', 'Windows file-copy APIs are needed.')
class SoundStorageNativeTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='momentum_sound_storage_')
        self.install = Path(self.work.name)
        self.addon = self.install / 'addons/momentum'
        self.bundled = self.addon / 'sounds'
        self.permanent = self.install / 'config/addons/momentum/sounds'
        self.bundled.mkdir(parents=True)
        (self.addon / 'bin').mkdir()
        for name in ('momentum-sound.exe', 'momentum-sound-launch.dll'):
            (self.addon / 'bin' / name).write_bytes(b'Fake helper; playback is stubbed in these file tests.')
        self.lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().test_exists = lambda path: Path(path).exists() or path.endswith(('momentum-sound.exe', 'momentum-sound-launch.dll'))
        self.lua.globals().test_mkdir = lambda path: Path(path).mkdir(parents=True, exist_ok=True)
        self.lua.globals().test_install = str(self.install)
        self.lua.globals().test_addon = str(self.addon)
        self.lua.execute('package.path = ... .. "/?.lua;" .. package.path', (ROOT / 'momentum').as_posix())
        self.lua.execute('''
            addon = { path = test_addon };
            AshitaCore = { GetInstallPath = function() return test_install; end };
            ashita = { fs = { exists = test_exists, create_dir = test_mkdir } };
            package.loaded['core.sound_worker'] = { new = function()
                return { start = function(_, path) test_played_path = path; return true; end };
            end };
            test_sound = require('core.sound');
        ''')
        self.sound = self.lua.globals().test_sound

    def tearDown(self):
        self.lua = None
        self.work.cleanup()

    def test_copy_survives_replacing_addon_audio_without_selection_changes(self):
        name = 'Fish & chips.wav'
        source = self.bundled / name
        source.write_bytes(b'custom audio\x00\xff')
        self.assertTrue(self.sound.use(name, True))
        okay, message = self.sound.save_custom(name)
        self.assertTrue(okay, message)
        self.assertEqual(source.read_bytes(), b'custom audio\x00\xff')
        self.assertEqual((self.permanent / name).read_bytes(), source.read_bytes())
        self.assertTrue(self.sound.is_open(name))
        source.unlink()
        self.sound.invalidate()
        self.assertEqual(self.sound.location(name)['kind'], 'permanent')
        self.assertTrue(self.sound.play(50))
        self.assertEqual(self.lua.globals().test_played_path, str(self.permanent / name))

    def test_case_insensitive_collision_keeps_both_files_and_selection(self):
        source = self.bundled / 'Alert.wav'
        source.write_bytes(b'new source')
        self.permanent.mkdir(parents=True)
        destination = self.permanent / 'alert.WAV'
        destination.write_bytes(b'older permanent sound')
        self.assertTrue(self.sound.use('Alert.wav', True))
        okay, message = self.sound.save_custom('Alert.wav')
        self.assertFalse(okay)
        self.assertIn('already exists', message)
        self.assertEqual(source.read_bytes(), b'new source')
        self.assertEqual(destination.read_bytes(), b'older permanent sound')
        self.assertTrue(self.sound.is_open('Alert.wav'))

    def test_unicode_filename_enumerates_copies_and_survives_refresh(self):
        name = '\u97f3\u91cf \U0001f3b5.wav'
        source = self.bundled / name
        source.write_bytes(b'custom Unicode audio\x00\xff')
        self.sound.refresh()
        self.assertIn(name, list(self.sound.files().values()))
        self.assertTrue(self.sound.use(name, True))
        okay, message = self.sound.save_custom(name)
        self.assertTrue(okay, message)
        self.assertEqual((self.permanent / name).read_bytes(), source.read_bytes())
        self.assertTrue(self.sound.location(name)['saved_copy'])
        self.sound.refresh()
        location = self.sound.location(name)
        self.assertFalse(location['saved_copy'])
        self.assertTrue(location['permanent_exists'])
        self.assertFalse(location['can_save'])
        self.lua.execute("package.loaded['core.sound'] = nil; test_sound = require('core.sound')")
        self.sound = self.lua.globals().test_sound
        self.assertTrue(self.sound.location(name)['permanent_exists'])
        self.assertFalse(self.sound.location(name)['can_save'])
        source.unlink()
        self.sound.invalidate()
        self.assertEqual(self.sound.location(name)['kind'], 'permanent')
        self.assertTrue(self.sound.use(name, True))
        self.assertTrue(self.sound.play(0))
        self.assertEqual(self.lua.globals().test_played_path, str(self.permanent / name))

    def test_legacy_ansi_selection_finds_the_same_unicode_filename(self):
        name = 'caf\u00e9.wav'
        (self.bundled / name).write_bytes(b'legacy audio')
        self.lua.execute("legacy_sound_name = 'caf' .. string.char(233) .. '.wav'")
        legacy = self.lua.eval("function() return test_sound.use(legacy_sound_name, true) end")
        import ctypes
        if ctypes.windll.kernel32.GetACP() != 1252:
            self.skipTest('This legacy byte fixture uses Windows codepage 1252.')
        self.assertTrue(legacy())
        self.assertTrue(self.sound.is_open(name))
        self.assertTrue(self.sound.play(0))
        self.assertEqual(self.lua.globals().test_played_path, str(self.bundled / name))

    def test_long_legacy_filename_limit_counts_characters_after_conversion(self):
        import ctypes
        if ctypes.windll.kernel32.GetACP() != 1252:
            self.skipTest('This legacy byte fixture uses Windows codepage 1252.')
        name = '\u00e9' * 190 + '.wav'
        (self.bundled / name).write_bytes(b'long legacy audio')
        self.lua.execute("legacy_sound_name = string.rep(string.char(233), 190) .. '.wav'")
        self.assertTrue(self.lua.eval("function() return test_sound.use(legacy_sound_name, true) end")())
        self.assertTrue(self.sound.is_open(name))
        okay, message = self.sound.save_custom(name)
        self.assertTrue(okay, message)
        self.assertEqual((self.permanent / name).read_bytes(), b'long legacy audio')

    def test_unicode_case_alias_keeps_failure_guard_without_linguistic_folding(self):
        for name in ('CAF\u00c9.wav', 'Stra\u00dfe.wav', 'STRASSE.wav'):
            (self.bundled / name).write_bytes(b'fake audio; playback is stubbed')
        self.lua.execute('''
            test_launches, test_comparisons = 0, 0;
            local paths = require('core.sound_paths');
            local compare = paths.same_name;
            paths.same_name = function(...)
                test_comparisons = test_comparisons + 1;
                return compare(...);
            end;
            package.loaded['core.sound_worker'] = { new = function()
                return {
                    start = function() test_launches = test_launches + 1; return true; end,
                    update = function()
                        if test_fail_next then test_fail_next = false; return { problem = 'Broken file' }; end
                    end,
                };
            end };
            package.loaded['core.sound'] = nil;
            test_sound = require('core.sound');
        ''')
        self.sound = self.lua.globals().test_sound
        self.assertTrue(self.sound.use('CAF\u00c9.wav', True))
        self.assertTrue(self.sound.play(0))
        self.lua.globals().test_fail_next = True
        self.sound.update(1)
        self.assertEqual(self.sound.problem('caf\u00e9.wav'), 'Broken file')
        comparisons = self.lua.globals().test_comparisons
        for _ in range(120):
            self.assertFalse(self.sound.use('caf\u00e9.wav', False))
            self.assertEqual(self.sound.problem('caf\u00e9.wav'), 'Broken file')
        self.assertEqual(self.lua.globals().test_comparisons, comparisons,
                         'Repeated alias lookups must not make per-frame native comparison loops.')
        self.assertEqual(self.lua.globals().test_launches, 1)
        self.assertTrue(self.sound.use('caf\u00e9.wav', True))
        self.assertIsNone(self.sound.problem('CAF\u00c9.wav'))
        self.assertTrue(self.sound.use('Stra\u00dfe.wav', True))
        self.assertTrue(self.sound.play(0))
        self.lua.globals().test_fail_next = True
        self.sound.update(2)
        self.assertTrue(self.sound.use('STRASSE.wav', False),
                        'Distinct Windows filenames must not be merged by linguistic ss/sharp-s folding.')
        self.assertTrue(self.sound.play(0))
        self.assertEqual(self.sound.problem('Stra\u00dfe.wav'), 'Broken file')
        self.assertIsNone(self.sound.problem('STRASSE.wav'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
