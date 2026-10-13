"""Check public documentation, local links and accidental private files."""
from collections import Counter
import os
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

from build_release import PRIVATE, ROOT, addon_version

SKIP = {'.git', '.ci', '.venv', '__pycache__', 'dist'}
TEXT = {'.lua', '.py', '.md', '.txt', '.yml', '.json', '.cpp', '.bat'}


def public_files(root):
    for folder, subfolders, files in os.walk(root):
        base = Path(folder)
        subfolders[:] = sorted(name for name in subfolders if name not in SKIP
                               and (base / name).relative_to(root).as_posix() not in {'tests/out', 'tests/preview/fonts'})
        for name in sorted(files):
            yield base / name


def anchors(text):
    result, seen = set(), Counter()
    for title in re.findall(r'^#{1,6}\s+(.+?)\s*#*$', text, re.M):
        slug = re.sub(r'[^\w\- ]', '', title.lower()).replace(' ', '-')
        result.add(slug if not seen[slug] else '%s-%d' % (slug, seen[slug]))
        seen[slug] += 1
    return result


def check(root=ROOT):
    root = Path(root).resolve()
    problems, documents = [], {}
    for path in public_files(root):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            problems.append(relative + ': linked source file')
        if path.suffix not in TEXT and path.name not in {'LICENSE', '.gitignore', '.gitattributes'}:
            documentation_image = path.suffix == '.png' and relative.startswith('docs/images/')
            if path.suffix != '.mp3' and not documentation_image:
                problems.append(relative + ': unexpected public file type')
            continue
        try:
            text = path.read_text(encoding='ascii')
        except UnicodeError:
            problems.append(relative + ': expected ASCII text')
            continue
        if PRIVATE.search(text):
            problems.append(relative + ': private path or credential marker')
        if path.suffix == '.md':
            documents[path.resolve()] = text
    for name in ('README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'docs/GUIDE.md', 'docs/RELEASING.md',
                 'tools/README.txt', 'tests/README.txt', 'LICENSE'):
        if not (root / name).is_file():
            problems.append(name + ': missing release document')
    version = addon_version(root / 'momentum')
    changelog = documents.get((root / 'CHANGELOG.md').resolve(), '')
    headings = re.findall(r'^## (.+)$', changelog, re.M)
    if 'Unreleased' in headings[1:]:
        problems.append('CHANGELOG.md: Unreleased must appear only once, at the top')
    if headings and headings[0] == 'Unreleased':
        headings = headings[1:]
    if not headings or headings[0] != version:
        problems.append('CHANGELOG.md: newest numbered section must match addon.version')
    links = 0
    for path, text in documents.items():
        for target in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)', text):
            target = target.strip('<>')
            split = urlsplit(target)
            if split.scheme or split.netloc:
                continue
            destination = (path.parent / unquote(split.path)).resolve() if split.path else path
            links += 1
            if not destination.is_relative_to(root) or not destination.exists():
                problems.append(path.relative_to(root).as_posix() + ': missing local link ' + target)
            elif split.fragment and destination in documents and unquote(split.fragment) not in anchors(documents[destination]):
                problems.append(path.relative_to(root).as_posix() + ': missing heading ' + target)
    return problems, links


if __name__ == '__main__':
    problems, links = check()
    for problem in problems:
        print('FAIL ' + problem)
    if problems:
        raise SystemExit(1)
    print('Public source and release documents checked; %d local links verified.' % links)
