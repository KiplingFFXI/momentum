"""Exercise production Lua sound paths and the isolated worker at zero volume."""
import ctypes
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
import time
import unittest
import wave

from lupa import luajit21

from test_sound_player import requires_audio_output

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('unicode_sound_launcher_builder', ROOT / 'tools/build_sound_launcher.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


@unittest.skipUnless(os.name == 'nt', 'Windows native sound paths are needed.')
class SoundUnicodeRuntimeTests(unittest.TestCase):
    @requires_audio_output
    def test_unicode_install_and_filename_play_through_production_lua(self):
        with tempfile.TemporaryDirectory(prefix='momentum_sound_unicode_') as work:
            folder = Path(work)
            install = folder / '\u97f3\u91cf'
            addon = install / 'addons/momentum'
            native = addon / 'bin'
            audio = install / 'config/addons/momentum/sounds' / '\u97f3\u91cf \U0001f3b5.wav'
            native.mkdir(parents=True)
            audio.parent.mkdir(parents=True)
            shutil.copy2(ROOT / 'momentum/bin/momentum-sound.exe', native / 'momentum-sound.exe')
            # The real release launcher is x86. Build the identical source for the
            # standalone LuaJIT test process architecture; no shipped file changes.
            library = folder / 'launcher.dll'
            builder.build(library, architecture='x64' if ctypes.sizeof(ctypes.c_void_p) == 8 else 'x86')
            shutil.copy2(library, native / 'momentum-sound-launch.dll')
            with wave.open(str(audio), 'wb') as stream:
                stream.setnchannels(1)
                stream.setsampwidth(2)
                stream.setframerate(22050)
                stream.writeframes(bytes(4410))
            lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
            lua.globals().test_install = str(install)
            lua.globals().test_addon = str(addon)
            lua.globals().test_filename = audio.name
            lua.execute('package.path = ... .. "/?.lua;" .. package.path', (ROOT / 'momentum').as_posix())
            lua.execute('''
                addon = { path = test_addon };
                AshitaCore = { GetInstallPath = function() return test_install; end };
                -- Native wide file APIs own all sound path operations. Returning
                -- to the Ashita regex/locale directory helper is a regression.
                ashita = { fs = setmetatable({}, { __index = function() error('Unexpected Ashita sound filesystem call'); end }) };
                test_sound = require('core.sound');
                test_sound.set_trace(function(event, fields)
                    if event == 'worker.exit' then test_exit_code = fields.code; end
                end);
                test_sound.refresh();
                assert(test_sound.find(test_filename) == test_filename);
                assert(test_sound.use(test_filename, true));
                assert(test_sound.play(0));
            ''')
            try:
                started = time.monotonic()
                while time.monotonic() - started < 8 and lua.globals().test_exit_code is None:
                    lua.globals().test_sound.update(time.monotonic() - started)
                    time.sleep(0.01)
                self.assertEqual(lua.globals().test_exit_code, 0, 'The real worker must complete from a Unicode root and filename.')
                self.assertIsNone(lua.globals().test_sound.problem(audio.name))
            finally:
                lua.globals().test_sound.close(True)
                lua = None


if __name__ == '__main__':
    unittest.main(verbosity=2)
