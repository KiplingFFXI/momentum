"""Validate and build the Momentum addon archive in Downloads."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import struct
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'momentum'
LICENSE = ROOT / 'LICENSE'
CORE = 'chains chat cooldowns dynamis dynamis_client dynamis_runtime events events_client events_runtime file_store food gil goals notifications packets phoenix_status player rings sessions sound sound_worker storage tracker'.split()
UI = 'defaults details dynamis dynamis_layout event_layout events fonts history hud job_icons layout migrate modes profiles readouts settings_window theme'.split()
HELPER = 'bin/momentum-sound.exe'
HELPER_SOURCE_MARKER = b'MOMENTUM_SOUND_PLAYER_SOURCE_SHA256='
LAUNCHER = 'bin/momentum-sound-launch.dll'
LAUNCHER_SOURCE_MARKER = b'MOMENTUM_SOUND_LAUNCHER_SOURCE_SHA256='
LAUNCHER_TEST_MARKER = b'MOMENTUM_SOUND_LAUNCHER_TEST_BUILD'
NATIVE = {
    HELPER: ('tools/build_sound_player.py', HELPER_SOURCE_MARKER, False),
    LAUNCHER: ('tools/build_sound_launcher.py', LAUNCHER_SOURCE_MARKER, True),
}
FILES = {'momentum.lua', 'data/phoenix_rules.lua', 'data/dynamis_rules.lua', 'data/event_rules.lua', 'sounds/README.txt', HELPER, LAUNCHER} | {'core/%s.lua' % name for name in CORE} | {'ui/%s.lua' % name for name in UI}
SOUNDS = {
    'sounds/FF VII Save.mp3': '1c86e387a56cbedf6c2d3401f9600924b6c1580a5f64b7d66813af529fbec5d7',
    'sounds/FF IX Moogle.mp3': '8aff95a7b14597e0701edf82af0c01af13a49a3cb460af34ce64246da28d7bd2',
}
DIRECTORIES = {'core', 'ui', 'data', 'sounds', 'bin'}
PRIVATE = re.compile(r'(?i)(?:[a-z]:[\\/]+Users[\\/]+|/(?:home|Users)/)[^\s\x00\'"<>]+|'
                     r'[\\/]\.(?:claude|codex)[\\/]|'
                     r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|'
                     r'\b(?:ghp_[a-zA-Z0-9]{30,}|github_pat_[a-zA-Z0-9_]{40,})\b')


def linked(path):
    return os.path.islink(path) or (hasattr(os.path, 'isjunction') and os.path.isjunction(path))


def addon_version(addon=ADDON):
    source = (Path(addon) / 'momentum.lua').read_text(encoding='ascii')
    match = re.search(r"^addon\.version\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)';", source, re.M)
    if not match:
        raise RuntimeError('momentum.lua must declare a version with three numeric parts.')
    return match.group(1)


def private_binary(data):
    if PRIVATE.search(data.decode('latin1')):
        return True
    for encoding in ('utf-16-le', 'utf-16-be'):
        for offset in (0, 1):
            if PRIVATE.search(data[offset:].decode(encoding, errors='ignore')):
                return True
    return False


def validate_native(data, name, source_root=ROOT):
    relative = name.removeprefix('momentum/')
    if relative not in NATIVE:
        raise RuntimeError('Unexpected native binary: ' + name)
    script_name, marker, library = NATIVE[relative]
    if len(data) < 64 or data[:2] != b'MZ':
        raise RuntimeError('Sound component is not a PE executable: ' + name)
    offset = struct.unpack_from('<I', data, 0x3C)[0]
    if offset < 64 or offset + 24 > len(data) or data[offset:offset + 4] != b'PE\0\0':
        raise RuntimeError('Sound component has an invalid PE header: ' + name)
    machine, sections = struct.unpack_from('<HH', data, offset + 4)
    optional_size, flags = struct.unpack_from('<HH', data, offset + 20)
    optional = offset + 24
    if machine != 0x14C or not flags & 2 or bool(flags & 0x2000) != library or optional_size < 96 \
            or optional + optional_size > len(data) or struct.unpack_from('<H', data, optional)[0] != 0x10B:
        kind = 'DLL' if library else 'executable'
        raise RuntimeError('Sound component must be a 32-bit x86 ' + kind + ': ' + name)
    if struct.unpack_from('<H', data, optional + 68)[0] != 2:
        raise RuntimeError('Sound component must use the Windows subsystem: ' + name)
    table = optional + optional_size
    if sections < 1 or sections > 32 or table + sections * 40 > len(data):
        raise RuntimeError('Sound component has an invalid section table: ' + name)
    for index in range(sections):
        size, start = struct.unpack_from('<II', data, table + index * 40 + 16)
        if size and (start < table + sections * 40 or start + size > len(data)):
            raise RuntimeError('Sound component has an invalid section range: ' + name)
    if private_binary(data):
        raise RuntimeError('Private path or credential marker in sound component: ' + name)
    if relative == LAUNCHER and LAUNCHER_TEST_MARKER in data:
        raise RuntimeError('Test launcher cannot be packaged: ' + name)
    script = Path(source_root) / script_name
    if not script.is_file():
        raise RuntimeError('Sound component source validator is missing: ' + script_name)
    spec = importlib.util.spec_from_file_location('momentum_sound_native_build', script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        digest = module.source_digest(root=Path(source_root))
    except (OSError, ValueError, RuntimeError) as error:
        raise RuntimeError('Sound component source could not be checked: ' + str(error)) from error
    markers = re.findall(re.escape(marker) + rb'([0-9a-f]{64})', data)
    if data.count(marker) != 1 or markers != [digest.encode('ascii')]:
        raise RuntimeError('Sound component is stale or has no matching source marker: ' + name)
    return data


def validate_helper(data, name, source_root=ROOT):
    if name.removeprefix('momentum/') != HELPER:
        raise RuntimeError('Unexpected sound helper: ' + name)
    return validate_native(data, name, source_root)


def checked_bytes(path, name, source_root=ROOT):
    if linked(path):
        raise RuntimeError('Linked release file: ' + name)
    data = Path(path).read_bytes()
    sound_name = name.removeprefix('momentum/')
    if sound_name in NATIVE:
        return validate_native(data, name, source_root)
    if Path(name).suffix.lower() in {'.exe', '.dll'}:
        raise RuntimeError('Unexpected native binary: ' + name)
    if sound_name in SOUNDS:
        if hashlib.sha256(data).hexdigest() != SOUNDS[sound_name]:
            raise RuntimeError('Sound asset hash mismatch: ' + name)
        return data
    data = data.replace(b'\r\n', b'\n')
    text = data.decode('ascii')
    if PRIVATE.search(text):
        raise RuntimeError('Private path or credential marker in ' + name)
    return data


def addon_files(addon=ADDON):
    addon = Path(addon)
    if linked(addon):
        raise RuntimeError('The addon folder must not be linked.')
    found = set()
    for folder, subfolders, names in os.walk(addon):
        for name in sorted(subfolders):
            path = Path(folder) / name
            relative = path.relative_to(addon).as_posix()
            if linked(path) or relative not in DIRECTORIES:
                raise RuntimeError('Unexpected or linked release folder: ' + relative)
        for name in sorted(names):
            path = Path(folder) / name
            relative = path.relative_to(addon).as_posix()
            if linked(path) or relative not in FILES | SOUNDS.keys():
                raise RuntimeError('Unexpected or linked release file: ' + relative)
            found.add(relative)
    missing = (FILES | SOUNDS.keys()) - found
    if missing:
        raise RuntimeError('Missing release files: ' + ', '.join(sorted(missing)))
    return [(addon / name, 'momentum/' + name) for name in sorted(found)]


def build(out, addon=ADDON, license_path=LICENSE):
    addon, out = Path(addon), Path(out)
    if out.resolve().is_relative_to(addon.resolve()):
        raise RuntimeError('Write the release archive outside the addon folder.')
    sources = [(Path(license_path), 'momentum/LICENSE')] + addon_files(addon)
    version = addon_version(addon)
    contents = [(name, checked_bytes(path, name)) for path, name in sources]
    for name in ('README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'docs/GUIDE.md', 'docs/RELEASING.md'):
        path = addon.parent / name
        if path.exists():
            checked_bytes(path, name)
    out.mkdir(parents=True, exist_ok=True)
    path = out / ('momentum-%s.zip' % version)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.momentum-', suffix='.zip', dir=out, delete=False) as handle:
            temporary = Path(handle.name)
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in contents:
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() or archive.namelist() != [name for name, _ in contents]:
                raise RuntimeError('The release archive did not pass verification.')
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return path, len(contents), hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=Path.home() / 'Downloads')
    args = parser.parse_args()
    path, count, digest = build(args.out)
    print('Wrote %s with %d files.' % (path, count))
    print('SHA-256 ' + digest)


if __name__ == '__main__':
    main()
