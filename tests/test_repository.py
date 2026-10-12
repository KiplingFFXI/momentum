"""Check the release notes and public-document validation used by CI."""
from contextlib import chdir
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_repository
import release_notes


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='momentum_docs_')
        self.root = Path(self.work.name)
        for name in ('README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'docs/GUIDE.md', 'docs/RELEASING.md',
                     'tests/README.txt', 'tools/README.txt', 'LICENSE', 'momentum/momentum.lua'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('# Test\n', encoding='ascii')
        (self.root / 'momentum/momentum.lua').write_text("addon.version = '1.0.0';\n", encoding='ascii')
        (self.root / 'CHANGELOG.md').write_text('# Changelog\n\n## 1.0.0\n\nInitial release.\n', encoding='ascii')

    def tearDown(self):
        self.work.cleanup()

    def test_local_links_and_repeated_heading_anchors(self):
        (self.root / 'docs/GUIDE.md').write_text('# Guide\n\n## EXP/HR\n\n## EXP/HR\n', encoding='ascii')
        (self.root / 'README.md').write_text('[guide](docs/GUIDE.md#exphr-1)\n', encoding='ascii')
        problems, links = check_repository.check(self.root)
        self.assertEqual(problems, [])
        self.assertEqual(links, 1)
        (self.root / 'README.md').write_text('[guide](docs/GUIDE.md#missing)\n', encoding='ascii')
        self.assertTrue(any('missing heading' in item for item in check_repository.check(self.root)[0]))

    def test_missing_link_private_path_and_version_are_rejected(self):
        (self.root / 'README.md').write_text('[guide](absent.md)\n' + 'C:/' + 'Users/Example/private.txt\n', encoding='ascii')
        (self.root / 'CHANGELOG.md').write_text('# Changelog\n\n## 2.0.0\n', encoding='ascii')
        problems, _ = check_repository.check(self.root)
        for text in ('missing local link', 'private path', 'match addon.version'):
            self.assertTrue(any(text in item for item in problems), problems)

    def test_relative_and_aliased_roots_report_link_problems(self):
        (self.root / 'README.md').write_text(
            '[guide](docs/GUIDE.md#test)\n[missing](absent.md)\n[heading](docs/GUIDE.md#absent)\n',
            encoding='ascii')
        expected = [
            'README.md: missing local link absent.md',
            'README.md: missing heading docs/GUIDE.md#absent',
        ]
        with chdir(self.root.parent):
            for root in (Path(self.root.name), self.root / 'docs' / '..'):
                with self.subTest(root=root):
                    problems, links = check_repository.check(root)
                    self.assertEqual(problems, expected)
                    self.assertEqual(links, 3)

    def test_local_output_does_not_enter_public_source_check(self):
        path = self.root / 'tests/out/private.bin'
        path.parent.mkdir(parents=True)
        path.write_bytes(b'\x00\xff')
        self.assertEqual(check_repository.check(self.root)[0], [])

    def test_documentation_pngs_are_allowed_only_under_images(self):
        image = self.root / 'docs/images/example.png'
        image.parent.mkdir()
        image.write_bytes(b'\x89PNG\r\n\x1a\n')
        (self.root / 'README.md').write_text('![Bar](docs/images/example.png)\n', encoding='ascii')
        self.assertEqual(check_repository.check(self.root), ([], 1))

        (self.root / 'docs/example.png').write_bytes(image.read_bytes())
        (image.parent / 'unexpected.bin').write_bytes(b'\x00\xff')
        problems, links = check_repository.check(self.root)
        self.assertEqual(set(problems), {
            'docs/example.png: unexpected public file type',
            'docs/images/unexpected.bin: unexpected public file type',
        })
        self.assertEqual(links, 1)

    def test_release_notes_stop_at_next_version(self):
        text = '# Changelog\n\n## 1.0.1\n\n- New.\n\n## 1.0.0\n\n- Old.\n'
        self.assertEqual(release_notes.notes(text, '1.0.1'), '- New.\n')
        self.assertEqual(release_notes.notes(text, '1.0.0'), '- Old.\n')
        with self.assertRaises(ValueError):
            release_notes.notes(text, '1.0.2')
        with self.assertRaises(ValueError):
            release_notes.notes('## 1.0.0\n\n## 0.9.0\nEarlier.\n', '1.0.0')


if __name__ == '__main__':
    unittest.main(verbosity=2)
