"""Build and verify Momentum's small asynchronous process launcher."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ('native/sound_launcher.cpp', 'tools/build_sound_launcher.py')
MARKER = b'MOMENTUM_SOUND_LAUNCHER_SOURCE_SHA256='
TEST_MARKER = b'MOMENTUM_SOUND_LAUNCHER_TEST_BUILD'


def source_digest(root=ROOT):
    root = Path(root)
    hashes = {name: hashlib.sha256((root / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for name in INPUTS}
    return hashlib.sha256(json.dumps(hashes, sort_keys=True, separators=(',', ':')).encode('ascii')).hexdigest()


def verify_binary(path, root=ROOT, architecture='x86', allow_test=False):
    if architecture not in ('x86', 'x64'):
        raise ValueError('Choose x86 or x64.')
    data = Path(path).read_bytes()
    if data[:2] != b'MZ' or len(data) < 64:
        raise ValueError('Sound launcher is not a PE binary.')
    offset = struct.unpack_from('<I', data, 0x3C)[0]
    if offset < 64 or offset + 24 + 70 > len(data):
        raise ValueError('Sound launcher has a truncated PE header.')
    machine, magic = (0x14C, 0x10B) if architecture == 'x86' else (0x8664, 0x20B)
    if data[offset:offset + 4] != b'PE\0\0' or struct.unpack_from('<H', data, offset + 4)[0] != machine:
        raise ValueError('Sound launcher must target ' + architecture + '.')
    if struct.unpack_from('<H', data, offset + 24)[0] != magic or not struct.unpack_from('<H', data, offset + 22)[0] & 0x2000:
        raise ValueError('Sound launcher must be a native Windows DLL.')
    if struct.unpack_from('<H', data, offset + 24 + 68)[0] != 2:
        raise ValueError('Sound launcher must use the Windows GUI subsystem.')
    expected = MARKER + source_digest(root).encode('ascii')
    if data.count(MARKER) != 1 or expected not in data:
        raise ValueError('Sound launcher is stale. Run tools/build_sound_launcher.py.')
    if TEST_MARKER in data and not allow_test:
        raise ValueError('Test launchers cannot be packaged.')
    if re.search(rb'[A-Za-z]:[\\/](?:Users|Documents and Settings)[\\/]', data, re.I):
        raise ValueError('Sound launcher contains a personal build path.')
    return {'machine': architecture, 'subsystem': 2, 'source_sha256': source_digest(root),
            'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}


def toolchain(architecture):
    finder = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    install = Path(subprocess.check_output([str(finder), '-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], text=True).strip())
    version = sorted((install / 'VC/Tools/MSVC').iterdir(), key=lambda path: tuple(map(int, path.name.split('.'))))[-1]
    kits = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Windows Kits/10'
    include = kits / 'Include'
    sdks = [path.name for path in include.iterdir()
            if path.is_dir() and re.fullmatch(r'[0-9]+(?:\.[0-9]+){3}', path.name)] if include.is_dir() else []
    if not sdks:
        raise RuntimeError('A Windows SDK with a four-part version is required.')
    sdk = max(sdks, key=lambda value: tuple(map(int, value.split('.'))))
    env = os.environ.copy()
    for name in ('CL', '_CL_', 'LINK', '_LINK_'):
        env.pop(name, None)
    binary = version / 'bin/Hostx64' / architecture
    env['PATH'] = os.pathsep.join([str(binary), env.get('PATH', '')])
    env['INCLUDE'] = ';'.join(map(str, [version / 'include', kits / 'Include' / sdk / 'ucrt', kits / 'Include' / sdk / 'shared', kits / 'Include' / sdk / 'um']))
    env['LIB'] = ';'.join(map(str, [version / 'lib' / architecture, kits / 'Lib' / sdk / 'um' / architecture]))
    return binary, env


def build(output=None, root=ROOT, architecture='x86', delay_before=0, delay_after=0, fail_cancel=False):
    root = Path(root)
    if architecture not in ('x86', 'x64') or any(type(value) is not int or not 0 <= value <= 10000 for value in (delay_before, delay_after)):
        raise ValueError('Choose x86 or x64 and delays from0 to10000ms.')
    runtime = (root / 'momentum/bin').resolve()
    output = Path(output).resolve() if output else runtime / 'momentum-sound-launch.dll'
    test_build = bool(delay_before or delay_after or fail_cancel)
    if (architecture != 'x86' or test_build) and (output == runtime or runtime in output.parents):
        raise ValueError('Test launchers must stay outside the addon folder.')
    output.parent.mkdir(parents=True, exist_ok=True)
    binary, env = toolchain(architecture)
    digest = source_digest(root)
    with tempfile.TemporaryDirectory(prefix='momentum_launcher_build_') as temporary:
        folder = Path(temporary)
        library = folder / 'momentum-sound-launch.dll'
        object_file = folder / 'sound_launcher.obj'
        definition = folder / 'launcher.def'
        names = ('begin', 'poll', 'cancel', 'release')
        definition.write_text('EXPORTS\n' + ''.join('momentum_launch_%s\n' % name for name in names), encoding='ascii')
        arguments = [str(binary / 'cl.exe'), '/nologo', '/c', '/std:c++17', '/O2', '/Oi', '/GS-', '/Zl', '/GR-', '/W4', '/WX', '/Brepro',
            '/d1trimfile:' + str(root.resolve()) + os.sep, '/DMOMENTUM_SOURCE_HASH="' + digest + '"',
            '/DMOMENTUM_LAUNCH_TEST_DELAY_BEFORE=' + str(delay_before), '/DMOMENTUM_LAUNCH_TEST_DELAY_AFTER=' + str(delay_after),
            '/DMOMENTUM_LAUNCH_TEST_FAIL_CANCEL=' + str(int(bool(fail_cancel))),
            str(root / 'native/sound_launcher.cpp'), '/Fo' + str(object_file)]
        result = subprocess.run(arguments, cwd=folder, env=env, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        arguments = [str(binary / 'link.exe'), '/NOLOGO', '/DLL', '/NODEFAULTLIB', '/MACHINE:' + architecture.upper(), '/SUBSYSTEM:WINDOWS',
            '/ENTRY:' + ('DllMain@12' if architecture == 'x86' else 'DllMain'), '/DEF:' + str(definition), '/OUT:' + str(library),
            '/INCREMENTAL:NO', '/OPT:REF', '/OPT:ICF', '/Brepro', '/DEBUG:NONE', '/DYNAMICBASE', '/NXCOMPAT', str(object_file), 'kernel32.lib']
        result = subprocess.run(arguments, cwd=folder, env=env, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        verify_binary(library, root, architecture, allow_test=test_build)
        output.write_bytes(library.read_bytes())
    return verify_binary(output, root, architecture, allow_test=test_build)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--arch', choices=('x86', 'x64'), default='x86')
    parser.add_argument('--test-delay-before', type=int, default=0)
    parser.add_argument('--test-delay-after', type=int, default=0)
    parser.add_argument('--test-fail-cancel', action='store_true')
    parser.add_argument('--allow-test', action='store_true')
    args = parser.parse_args()
    output = args.out or ROOT / 'momentum/bin/momentum-sound-launch.dll'
    print(json.dumps(verify_binary(output, architecture=args.arch, allow_test=args.allow_test) if args.check else build(output,
        architecture=args.arch, delay_before=args.test_delay_before, delay_after=args.test_delay_after,
        fail_cancel=args.test_fail_cancel), indent=2))


if __name__ == '__main__':
    main()
