"""Check native asynchronous launch ownership without a game or audio playback."""
import ctypes
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_sound_launcher', ROOT / 'tools/build_sound_launcher.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
DLL = ROOT / 'momentum/bin/momentum-sound-launch.dll'


def dll_names(data):
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    count, optional_size = struct.unpack_from('<H', data, pe + 6)[0], struct.unpack_from('<H', data, pe + 20)[0]
    sections = pe + 24 + optional_size

    def raw(rva):
        for index in range(count):
            size, start, disk_size, disk = struct.unpack_from('<IIII', data, sections + index * 40 + 8)
            if start <= rva < start + max(size, disk_size):
                return disk + rva - start
        raise ValueError('Unmapped PE address.')

    directories = pe + 24 + (96 if struct.unpack_from('<H', data, pe + 24)[0] == 0x10B else 112)
    descriptor = raw(struct.unpack_from('<I', data, directories + 8)[0])
    imports = set()
    while any(data[descriptor:descriptor + 20]):
        name = raw(struct.unpack_from('<I', data, descriptor + 12)[0])
        imports.add(data[name:data.index(b'\0', name)].decode('ascii').lower())
        descriptor += 20
    return imports


class ProcessInformation(ctypes.Structure):
    _fields_ = [('hProcess', ctypes.c_void_p), ('hThread', ctypes.c_void_p),
                ('dwProcessId', ctypes.c_uint32), ('dwThreadId', ctypes.c_uint32)]


if os.name == 'nt':
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    for name, args, result in (
        ('LoadLibraryW', [ctypes.c_wchar_p], ctypes.c_void_p),
        ('GetModuleHandleW', [ctypes.c_wchar_p], ctypes.c_void_p),
        ('FreeLibrary', [ctypes.c_void_p], ctypes.c_int),
        ('GetProcAddress', [ctypes.c_void_p, ctypes.c_char_p], ctypes.c_void_p),
        ('OpenProcess', [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32], ctypes.c_void_p),
        ('TerminateProcess', [ctypes.c_void_p, ctypes.c_uint32], ctypes.c_int),
        ('WaitForSingleObject', [ctypes.c_void_p, ctypes.c_uint32], ctypes.c_uint32),
        ('CloseHandle', [ctypes.c_void_p], ctypes.c_int),
        ('GetCurrentProcess', [], ctypes.c_void_p),
        ('GetProcessHandleCount', [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)], ctypes.c_int),
    ):
        function = getattr(kernel, name)
        function.argtypes, function.restype = args, result


class NativeLibrary:
    """Hold the caller's DLL reference through every exported API return."""
    def __init__(self, path):
        self.path = Path(path)
        self.module = kernel.LoadLibraryW(str(self.path))
        if not self.module:
            raise ctypes.WinError(ctypes.get_last_error())
        self.begin = self.function('begin', ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_wchar_p)
        self.poll = self.function('poll', ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(ProcessInformation),
                                  ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32))
        self.cancel = self.function('cancel', None, ctypes.c_void_p)
        self.release = self.function('release', None, ctypes.c_void_p)

    def function(self, name, result, *arguments):
        address = kernel.GetProcAddress(self.module, ('momentum_launch_' + name).encode('ascii'))
        if not address:
            raise ctypes.WinError(ctypes.get_last_error())
        return ctypes.CFUNCTYPE(result, *arguments, use_last_error=True)(address)

    def close(self):
        if self.module:
            assert kernel.FreeLibrary(self.module)
            self.module = None

    def result(self, request):
        process, error, elapsed = ProcessInformation(), ctypes.c_uint32(), ctypes.c_uint32()
        status = self.poll(request, ctypes.byref(process), ctypes.byref(error), ctypes.byref(elapsed))
        return status, process, error.value, elapsed.value


class LauncherBinaryTests(unittest.TestCase):
    def test_release_is_small_x86_gui_dll_with_only_kernel32(self):
        metadata = builder.verify_binary(DLL)
        self.assertEqual(metadata['machine'], 'x86')
        self.assertEqual(metadata['subsystem'], 2)
        self.assertLess(metadata['bytes'], 16384)
        data = DLL.read_bytes()
        self.assertEqual(dll_names(data), {'kernel32.dll'})
        for name in ('begin', 'poll', 'cancel', 'release'):
            self.assertIn(('momentum_launch_' + name).encode('ascii') + b'\0', data)
        self.assertNotIn(b'RSDS', data)
        for value in (str(ROOT), str(Path.home())):
            for encoding in ('utf-8', 'utf-16-le', 'utf-16-be'):
                self.assertNotIn(value.encode(encoding).lower(), data.lower())

    def test_corrupt_or_stale_binary_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='momentum_launcher_bad_') as folder:
            path = Path(folder) / 'bad.dll'
            for data in (b'', b'MZ' + bytes(62), b'MZ' + bytes(58) + struct.pack('<I', 0xFFFFFFFF)):
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    builder.verify_binary(path)
            path.write_bytes(DLL.read_bytes().replace(builder.MARKER, b'X' * len(builder.MARKER)))
            with self.assertRaisesRegex(ValueError, 'stale'):
                builder.verify_binary(path)

    @unittest.skipUnless(os.name == 'nt', 'The Windows compiler is needed.')
    def test_reproducible_x86_build(self):
        with tempfile.TemporaryDirectory(prefix='momentum_launcher_build_test_') as folder:
            one, two = Path(folder) / 'one.dll', Path(folder) / 'two.dll'
            builder.build(one)
            builder.build(two)
            self.assertEqual(one.read_bytes(), two.read_bytes())
            self.assertEqual(builder.verify_binary(one)['source_sha256'], builder.verify_binary(DLL)['source_sha256'])


@unittest.skipUnless(os.name == 'nt', 'The native Windows launcher is needed.')
class LauncherRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix='momentum_launcher_native_')
        cls.folder = Path(cls.work.name)
        cls.arch = 'x64' if ctypes.sizeof(ctypes.c_void_p) == 8 else 'x86'
        cls.fast, cls.before, cls.after = (cls.folder / name for name in ('fast.dll', 'before.dll', 'after.dll'))
        cls.failed_cancel = cls.folder / 'failed_cancel.dll'
        builder.build(cls.fast, architecture=cls.arch)
        builder.build(cls.before, architecture=cls.arch, delay_before=700)
        builder.build(cls.after, architecture=cls.arch, delay_after=700)
        builder.build(cls.failed_cancel, architecture=cls.arch, delay_after=700, fail_cancel=True)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def setUp(self):
        self.test_work = tempfile.TemporaryDirectory(prefix='momentum_launcher_child_')
        self.test_folder = Path(self.test_work.name)
        self.libraries, self.requests, self.handles = [], [], []

    def tearDown(self):
        for library, request in self.requests:
            library.release(request)
        for handle in self.handles:
            kernel.TerminateProcess(handle, 125)
            kernel.WaitForSingleObject(handle, 3000)
            kernel.CloseHandle(handle)
        for library in self.libraries:
            library.close()
        self.test_work.cleanup()

    def library(self, path):
        library = NativeLibrary(path)
        self.libraries.append(library)
        return library

    def child(self, library, marker='started.txt'):
        path = self.test_folder / marker
        arguments = [sys.executable, '-c', "import os,sys,time; open(sys.argv[1],'w').write(str(os.getpid())); time.sleep(30)", str(path)]
        request = library.begin(sys.executable, subprocess.list2cmdline(arguments))
        self.assertTrue(request)
        self.requests.append((library, request))
        return request, path

    def drop(self, library, request):
        library.release(request)
        self.requests.remove((library, request))

    def ready(self, library, request):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            result = library.result(request)
            if result[0] != 0:
                return result
            time.sleep(0.005)
        self.fail('Native launch did not finish.')

    def observed_child(self, marker):
        end = time.monotonic() + 3
        while not marker.exists() and time.monotonic() < end:
            time.sleep(0.005)
        self.assertTrue(marker.exists(), 'Child did not start.')
        process = kernel.OpenProcess(0x100001, False, int(marker.read_text()))
        self.assertTrue(process)
        self.handles.append(process)
        return process

    def test_slow_launch_returns_pending_without_waiting_on_caller(self):
        library = self.library(self.before)
        start = time.perf_counter()
        request, marker = self.child(library)
        begin_ms = (time.perf_counter() - start) * 1000
        self.assertLess(begin_ms, 250)
        status, process, error, elapsed = library.result(request)
        self.assertEqual((status, process.hProcess, error, elapsed), (0, None, 0, 0))
        status, process, error, elapsed = self.ready(library, request)
        self.assertEqual((status, error), (1, 0))
        self.assertGreaterEqual(time.perf_counter() - start, 0.65)
        self.assertLess(elapsed, 700)
        self.handles.append(process.hProcess)
        self.assertTrue(kernel.CloseHandle(process.hThread))
        self.assertEqual(library.result(request)[2], 183)
        self.drop(library, request)
        self.assertEqual(kernel.WaitForSingleObject(process.hProcess, 0), 258)
        print('  caller begin %.3fms; native CreateProcess %dms' % (begin_ms, elapsed))

    def test_missing_program_failure_keeps_no_handles(self):
        library = self.library(self.fast)
        missing = str(self.test_folder / 'missing.exe')
        request = library.begin(missing, '"' + missing + '"')
        self.assertTrue(request)
        self.requests.append((library, request))
        status, process, error, unused = self.ready(library, request)
        self.assertEqual((status, process.hProcess, process.hThread), (-1, None, None))
        self.assertEqual(error, 2)

    def test_cancel_before_creation_stays_pending_until_producer_finishes(self):
        library = self.library(self.before)
        request, marker = self.child(library)
        library.cancel(request)
        self.assertEqual(library.result(request)[0], 0)
        status, process, error, elapsed = self.ready(library, request)
        self.assertEqual((status, process.hProcess, error, elapsed), (-1, None, 1223, 0))
        self.assertFalse(marker.exists())

    def test_cancel_after_creation_reaps_child_before_publish(self):
        library = self.library(self.after)
        request, marker = self.child(library)
        child = self.observed_child(marker)
        self.assertEqual(library.result(request)[0], 0)
        library.cancel(request)
        status, process, error, unused = self.ready(library, request)
        self.assertEqual((status, process.hProcess, error), (-1, None, 1223))
        self.assertEqual(kernel.WaitForSingleObject(child, 2000), 0)

    def test_cancel_after_publish_transfers_handle_for_caller_cleanup(self):
        library = self.library(self.fast)
        request, marker = self.child(library)
        self.observed_child(marker)
        time.sleep(0.05)
        library.cancel(request)
        status, process, error, unused = self.ready(library, request)
        self.assertEqual((status, error), (1, 0))
        self.handles.append(process.hProcess)
        kernel.CloseHandle(process.hThread)
        self.drop(library, request)
        self.assertEqual(kernel.WaitForSingleObject(process.hProcess, 0), 258)

    def test_failed_native_cancellation_transfers_live_handles_for_caller_cleanup(self):
        library = self.library(self.failed_cancel)
        request, marker = self.child(library)
        child = self.observed_child(marker)
        library.cancel(request)
        status, process, error, unused = self.ready(library, request)
        self.assertEqual((status, error), (1, 0))
        self.assertEqual(kernel.WaitForSingleObject(child, 0), 258)
        self.handles.append(process.hProcess)
        kernel.CloseHandle(process.hThread)
        self.drop(library, request)
        self.assertEqual(kernel.WaitForSingleObject(process.hProcess, 0), 258)

    def test_staged_test_binary_cannot_pass_normal_release_verifier(self):
        with self.assertRaisesRegex(ValueError, 'Test launchers'):
            builder.verify_binary(self.before, architecture=self.arch)
        builder.verify_binary(self.before, architecture=self.arch, allow_test=True)

    def test_unload_with_pending_creation_keeps_native_code_until_thread_exit(self):
        library = self.library(self.after)
        request, marker = self.child(library)
        child = self.observed_child(marker)
        self.drop(library, request)
        library.close()
        self.assertTrue(kernel.GetModuleHandleW(str(self.after)))
        self.assertEqual(kernel.WaitForSingleObject(child, 3000), 0)
        end = time.monotonic() + 3
        while kernel.GetModuleHandleW(str(self.after)) and time.monotonic() < end:
            time.sleep(0.005)
        self.assertFalse(kernel.GetModuleHandleW(str(self.after)))

    def test_copied_buffers_and_no_handle_leak_across_repeated_requests(self):
        library = self.library(self.fast)
        for unused in range(10):
            request = library.begin(str(self.test_folder / 'missing.exe'), 'missing')
            self.ready(library, request)
            library.release(request)
        time.sleep(0.1)
        baseline = ctypes.c_uint32()
        kernel.GetProcessHandleCount(kernel.GetCurrentProcess(), ctypes.byref(baseline))
        for index in range(30):
            request = library.begin(str(self.test_folder / 'missing.exe'), 'missing')
            self.assertTrue(request)
            self.assertEqual(self.ready(library, request)[0], -1)
            library.release(request)
        final = ctypes.c_uint32()
        end = time.monotonic() + 2
        while time.monotonic() < end:
            kernel.GetProcessHandleCount(kernel.GetCurrentProcess(), ctypes.byref(final))
            if final.value <= baseline.value + 1:
                break
            time.sleep(0.01)
        self.assertLessEqual(final.value, baseline.value + 1)
        delayed = self.library(self.before)
        path = self.test_folder / 'copied.txt'
        app = ctypes.create_unicode_buffer(sys.executable)
        command = ctypes.create_unicode_buffer(subprocess.list2cmdline([sys.executable, '-c', "import sys;open(sys.argv[1],'w').write('copied')", str(path)]))
        request = delayed.begin(app, command)
        self.assertTrue(request)
        self.requests.append((delayed, request))
        app.value, command.value = 'bad', 'bad'
        status, process, error, unused = self.ready(delayed, request)
        self.assertEqual((status, error), (1, 0))
        self.handles.append(process.hProcess)
        kernel.CloseHandle(process.hThread)
        self.assertEqual(kernel.WaitForSingleObject(process.hProcess, 3000), 0)
        self.assertEqual(path.read_text(), 'copied')


if __name__ == '__main__':
    unittest.main(verbosity=2)
