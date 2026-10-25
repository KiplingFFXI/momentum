"""Exercise the isolated sound worker without audible playback or a game client."""
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_sound_player', ROOT / 'tools/build_sound_player.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
WORKER = ROOT / 'momentum/bin/momentum-sound.exe'
HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def imports(data):
    """Read DLL names directly so the test needs no external PE package."""
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    sections, optional_size = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    section_table = pe + 24 + optional_size

    def raw(rva):
        for index in range(sections):
            size, start, disk_size, disk = struct.unpack_from('<IIII', data, section_table + index * 40 + 8)
            if start <= rva < start + max(size, disk_size):
                return disk + rva - start
        raise ValueError('Unmapped PE address.')

    directory = struct.unpack_from('<I', data, pe + 24 + 96 + 8)[0]
    offset, result = raw(directory), set()
    while any(data[offset:offset + 20]):
        name = raw(struct.unpack_from('<I', data, offset + 12)[0])
        result.add(data[name:data.index(b'\0', name)].decode('ascii').lower())
        offset += 20
    return result


class SoundWorkerBinaryTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='momentum_worker_test_')
        self.folder = Path(self.work.name)

    def tearDown(self):
        self.work.cleanup()

    def test_current_x86_gui_binary_has_system_only_imports(self):
        verified = builder.verify_binary(WORKER)
        self.assertEqual(verified['machine'], 'x86')
        self.assertEqual(verified['subsystem'], 2)
        dependencies = imports(WORKER.read_bytes())
        self.assertEqual(dependencies, {'kernel32.dll', 'user32.dll', 'shell32.dll', 'winmm.dll', 'ole32.dll'})
        self.assertLess(verified['bytes'], 256 * 1024)
        data = WORKER.read_bytes()
        self.assertNotIn(b'RSDS', data)
        for text in (str(ROOT), str(Path.home())):
            for encoding in ('utf-8', 'utf-16-le', 'utf-16-be'):
                self.assertNotIn(text.encode(encoding).lower(), data.lower())

    def test_stale_source_and_bad_binary_are_rejected(self):
        source_root = self.folder / 'source'
        for name in builder.INPUTS:
            destination = source_root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        builder.verify_binary(WORKER, root=source_root)
        with (source_root / builder.INPUTS[0]).open('ab') as file:
            file.write(b'\n// Changed source.\n')
        with self.assertRaisesRegex(ValueError, 'stale'):
            builder.verify_binary(WORKER, root=source_root)
        broken = self.folder / 'broken.exe'
        for data in (b'', b'MZ' + bytes(62), b'MZ' + bytes(58) + struct.pack('<I', 0xFFFFFFFF)):
            broken.write_bytes(data)
            with self.assertRaises(ValueError):
                builder.verify_binary(broken)

    @unittest.skipUnless(os.name == 'nt', 'The x86 Windows compiler is needed.')
    def test_reproducible_build(self):
        first, second = self.folder / 'one.exe', self.folder / 'two.exe'
        builder.build(first)
        builder.build(second)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        self.assertEqual(builder.verify_binary(first)['source_sha256'], builder.verify_binary(WORKER)['source_sha256'])


@unittest.skipUnless(os.name == 'nt', 'The native Windows worker is needed.')
class SoundWorkerRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='momentum_worker_runtime_')
        self.folder = Path(self.work.name)

    def tearDown(self):
        self.work.cleanup()

    def run_worker(self, arguments, timeout=15):
        return subprocess.run([str(WORKER), *map(str, arguments)], timeout=timeout, creationflags=HIDDEN)

    def silent_play(self, sound, minimum, maximum=8):
        diagnostic = self.folder / 'worker.jsonl'
        diagnostic.unlink(missing_ok=True)
        start = time.monotonic()
        result = self.run_worker([sound, 0, os.getpid(), diagnostic])
        elapsed = time.monotonic() - start
        self.assertEqual(result.returncode, 0, diagnostic.read_text() if diagnostic.exists() else 'No diagnostic file.')
        self.assertGreaterEqual(elapsed, minimum)
        self.assertLess(elapsed, maximum)
        records = [json.loads(line) for line in diagnostic.read_text().splitlines()]
        started = [line for line in records if line['event'] == 'worker.playback.started']
        completed = [line for line in records if line['event'] == 'worker.playback.completed']
        self.assertEqual(len(started), 1)
        self.assertEqual(len(completed), 1)
        self.assertGreaterEqual(completed[0]['elapsed_ms'] - started[0]['elapsed_ms'], int(minimum * 1000) - 100)
        self.assertEqual(len([line for line in records if line['operation'] == 'open' and line['event'] == 'worker.native.before']), 1)
        self.assertTrue(all(line['code'] == 0 for line in records))
        self.assertLess(len(records), 28)
        self.assertNotIn(str(sound), diagnostic.read_text())
        print('  silent playback:', sound.name.encode('ascii', 'backslashreplace').decode('ascii'), '%.3fs' % elapsed,
              'playing=%dms' % (completed[0]['elapsed_ms'] - started[0]['elapsed_ms']))

    def test_bundled_mp3s_play_sequentially_in_separate_workers_at_zero_volume(self):
        self.silent_play(ROOT / 'momentum/sounds/FF VII Save.mp3', 1.3)
        self.silent_play(ROOT / 'momentum/sounds/FF IX Moogle.mp3', 1.7)

    def test_custom_wav_unicode_path_plays_at_zero_volume(self):
        sound = self.folder / 'Custom \u97f3\u91cf test.wav'
        with wave.open(str(sound), 'wb') as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(22050)
            file.writeframes(bytes(22050 * 2))
        self.silent_play(sound, 0.8)

    def test_very_short_custom_wav_completes_at_zero_volume(self):
        sound = self.folder / 'short.wav'
        with wave.open(str(sound), 'wb') as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(22050)
            file.writeframes(bytes(110 * 2))
        self.silent_play(sound, 0)

    def test_long_custom_wav_is_not_cut_off_by_native_call_watchdog(self):
        sound = self.folder / 'long.wav'
        with wave.open(str(sound), 'wb') as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(22050)
            file.writeframes(bytes(22050 * 2 * 12))
        self.silent_play(sound, 11.5, 15)

    def test_bad_arguments_missing_and_invalid_file_have_stable_errors(self):
        self.assertEqual(self.run_worker(['--self-test']).returncode, 0)
        self.assertEqual(self.run_worker([]).returncode, 2)
        self.assertEqual(self.run_worker(['relative.mp3', 0, os.getpid(), '']).returncode, 2)
        missing = self.folder / 'missing.mp3'
        self.assertEqual(self.run_worker([missing, 1001, os.getpid(), '']).returncode, 2)
        self.assertEqual(self.run_worker([missing, 0, os.getpid(), '']).returncode, 3)
        invalid = self.folder / 'invalid.mp3'
        invalid.write_bytes(b'This is not MP3 audio.')
        self.assertEqual(self.run_worker([invalid, 0, os.getpid(), '']).returncode, 3)

    def test_parent_death_cancels_only_worker(self):
        parent = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(1)'], creationflags=HIDDEN)
        child = subprocess.Popen([str(WORKER), '--self-test-parent', str(parent.pid)], creationflags=HIDDEN)
        try:
            self.assertEqual(parent.wait(timeout=5), 0)
            self.assertEqual(child.wait(timeout=5), 125)
        finally:
            if parent.poll() is None:
                parent.kill()
            if child.poll() is None:
                child.kill()
            parent.wait()
            child.wait()

    def test_stalled_call_watchdog_exits_after_ten_seconds(self):
        start = time.monotonic()
        result = self.run_worker(['--self-test-timeout', os.getpid()], timeout=15)
        self.assertEqual(result.returncode, 7)
        self.assertGreaterEqual(time.monotonic() - start, 9.5)
        self.assertLess(time.monotonic() - start, 14)

    def test_retained_handle_can_cancel_worker(self):
        child = subprocess.Popen([str(WORKER), '--self-test-parent', str(os.getpid())], creationflags=HIDDEN)
        try:
            self.assertIsNone(child.poll())
            terminate = ctypes.WinDLL('kernel32', use_last_error=True).TerminateProcess
            terminate.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
            terminate.restype = ctypes.c_int
            self.assertTrue(terminate(int(child._handle), 125))
            self.assertEqual(child.wait(timeout=5), 125)
        finally:
            if child.poll() is None:
                child.kill()
            child.wait()


if __name__ == '__main__':
    unittest.main(verbosity=2)
