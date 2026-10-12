"""Copy the current version's changelog into a release notes file."""
import argparse
from pathlib import Path
import re

from build_release import ROOT, addon_version


def notes(changelog, version):
    match = re.search(r'^## ' + re.escape(version) + r'\s*\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
    if not match or not match.group(1).strip():
        raise ValueError('CHANGELOG.md has no notes for ' + version)
    return match.group(1).strip() + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    version = addon_version()
    text = notes((ROOT / 'CHANGELOG.md').read_text(encoding='ascii'), version)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding='ascii', newline='\n')
    print('version=' + version)
