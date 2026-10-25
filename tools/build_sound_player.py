"""Build and verify Momentum's isolated 32-bit sound worker."""
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
INPUTS = ('native/sound_player.cpp', 'tools/build_sound_player.py')
MARKER = b'MOMENTUM_SOUND_PLAYER_SOURCE_SHA256='


def source_digest(root=ROOT):
    root = Path(root)
    hashes = {name: hashlib.sha256((root / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for name in INPUTS}
    return hashlib.sha256(json.dumps(hashes, sort_keys=True, separators=(',', ':')).encode('ascii')).hexdigest()


def verify_binary(path, root=ROOT):
    data = Path(path).read_bytes()
    if data[:2] != b'MZ' or len(data) < 64:
        raise ValueError('Sound worker is not a PE binary.')
    offset = struct.unpack_from('<I', data, 0x3C)[0]
    if offset < 64 or offset + 24 + 70 > len(data):
        raise ValueError('Sound worker has a truncated PE header.')
    if data[offset:offset + 4] != b'PE\0\0' or struct.unpack_from('<H', data, offset + 4)[0] != 0x14C:
        raise ValueError('Sound worker must target x86.')
    if struct.unpack_from('<H', data, offset + 24)[0] != 0x10B:
        raise ValueError('Sound worker must use PE32.')
    if struct.unpack_from('<H', data, offset + 24 + 68)[0] != 2:
        raise ValueError('Sound worker must use the Windows GUI subsystem.')
    expected = MARKER + source_digest(root).encode('ascii')
    if data.count(MARKER) != 1 or expected not in data:
        raise ValueError('Sound worker is stale. Run tools/build_sound_player.py.')
    if re.search(rb'[A-Za-z]:[\\/](?:Users|Documents and Settings)[\\/]', data, re.I):
        raise ValueError('Sound worker contains a personal build path.')
    return {'machine': 'x86', 'subsystem': struct.unpack_from('<H', data, offset + 24 + 68)[0],
            'source_sha256': source_digest(root), 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}


def toolchain():
    finder = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    install = Path(subprocess.check_output([str(finder), '-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], text=True).strip())
    version = sorted((install / 'VC/Tools/MSVC').iterdir(), key=lambda path: tuple(map(int, path.name.split('.'))))[-1]
    kits = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Windows Kits/10'
    sdk = sorted((path.name for path in (kits / 'Include').iterdir() if path.is_dir()), key=lambda value: tuple(map(int, value.split('.'))))[-1]
    env = os.environ.copy()
    for name in ('CL', '_CL_', 'LINK', '_LINK_'):
        env.pop(name, None)
    env['PATH'] = os.pathsep.join([str(version / 'bin/Hostx64/x86'), env.get('PATH', '')])
    env['INCLUDE'] = ';'.join(map(str, [version / 'include', kits / 'Include' / sdk / 'ucrt', kits / 'Include' / sdk / 'shared', kits / 'Include' / sdk / 'um']))
    env['LIB'] = ';'.join(map(str, [version / 'lib/x86', kits / 'Lib' / sdk / 'ucrt/x86', kits / 'Lib' / sdk / 'um/x86']))
    return version / 'bin/Hostx64/x86/cl.exe', env


def build(output=None, root=ROOT):
    root = Path(root)
    output = Path(output) if output else root / 'momentum/bin/momentum-sound.exe'
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    compiler, env = toolchain()
    digest = source_digest(root)
    with tempfile.TemporaryDirectory(prefix='momentum_sound_build_') as temporary:
        folder = Path(temporary)
        executable = folder / 'momentum-sound.exe'
        arguments = [str(compiler), '/nologo', '/std:c++17', '/O2', '/MT', '/EHsc', '/W4', '/WX', '/GR-', '/DNDEBUG', '/Brepro',
            '/d1trimfile:' + str(root.resolve()) + os.sep, '/DMOMENTUM_SOURCE_HASH="' + digest + '"',
            str(root / 'native/sound_player.cpp'), '/Fo' + str(folder / 'sound_player.obj'), '/Fe' + str(executable),
            '/link', '/MACHINE:X86', '/SUBSYSTEM:WINDOWS', '/INCREMENTAL:NO', '/OPT:REF', '/OPT:ICF', '/Brepro',
            '/DEBUG:NONE', 'kernel32.lib', 'user32.lib', 'shell32.lib', 'winmm.lib', 'ole32.lib']
        result = subprocess.run(arguments, cwd=folder, env=env, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        verify_binary(executable, root)
        output.write_bytes(executable.read_bytes())
    return verify_binary(output, root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    output = args.out or ROOT / 'momentum/bin/momentum-sound.exe'
    print(json.dumps(verify_binary(output) if args.check else build(output), indent=2))


if __name__ == '__main__':
    main()
