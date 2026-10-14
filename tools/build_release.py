"""Validate and build the Momentum addon archive in Downloads."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'momentum'
LICENSE = ROOT / 'LICENSE'
CORE = 'chains chat dynamis dynamis_client dynamis_runtime file_store food gil goals notifications packets phoenix_status player rings sessions sound tracker'.split()
UI = 'defaults details dynamis dynamis_layout fonts history hud job_icons layout migrate modes profiles readouts settings_window theme'.split()
FILES = {'momentum.lua', 'data/phoenix_rules.lua', 'data/dynamis_rules.lua', 'sounds/README.txt'} | {'core/%s.lua' % name for name in CORE} | {'ui/%s.lua' % name for name in UI}
SOUNDS = {
    'sounds/FF VII Save.mp3': '1c86e387a56cbedf6c2d3401f9600924b6c1580a5f64b7d66813af529fbec5d7',
    'sounds/FF IX Moogle.mp3': '8aff95a7b14597e0701edf82af0c01af13a49a3cb460af34ce64246da28d7bd2',
}
DIRECTORIES = {'core', 'ui', 'data', 'sounds'}
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


def checked_bytes(path, name):
    if linked(path):
        raise RuntimeError('Linked release file: ' + name)
    data = Path(path).read_bytes()
    sound_name = name.removeprefix('momentum/')
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
    parser.add_argument('--server', action='store_true', help='Also build the optional Phoenix server companion.')
    args = parser.parse_args()
    path, count, digest = build(args.out)
    print('Wrote %s with %d files.' % (path, count))
    print('SHA-256 ' + digest)
    if args.server:
        path, count, digest = build_server(args.out)
        print('Wrote %s with %d files.' % (path, count))
        print('SHA-256 ' + digest)


def build_server(out, server=ROOT / 'server', license_path=LICENSE):
    out, server = Path(out), Path(server)
    if linked(server) or out.resolve().is_relative_to(server.resolve()):
        raise RuntimeError('Keep server sources separate from the output archive.')
    expected = {'README.txt', 'momentum_status.lua', 'momentum_chain.cpp'}
    if {p.name for p in server.iterdir()} != expected:
        raise RuntimeError('Unexpected or missing server companion files.')
    contents = [(name, checked_bytes(server / name, name)) for name in sorted(expected)]
    contents.append(('LICENSE', checked_bytes(license_path, 'LICENSE')))
    out.mkdir(parents=True, exist_ok=True)
    path = out / ('momentum-phoenix-status-%s.zip' % addon_version())
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.momentum-server-', suffix='.zip', dir=out, delete=False) as handle:
            temporary = Path(handle.name)
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in contents:
                entry = zipfile.ZipInfo('momentum-status-server/' + name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() or archive.namelist() != ['momentum-status-server/' + name for name, _ in contents]:
                raise RuntimeError('The server companion archive did not pass verification.')
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return path, len(contents), hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == '__main__':
    main()
