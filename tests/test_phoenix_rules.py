"""Check EXP YAML indexing, enabled overlays, and the server loader contract."""

from pathlib import Path
import sys
import unittest

from lupa import LuaRuntime
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import export_rules as exporter


class MemorySource:
    def __init__(self, documents):
        self.documents = documents
        self.paths = set(documents)
        self.texts = {}

    def yaml(self, path):
        text = self.documents[path]
        self.texts[path] = text
        return yaml.safe_load(text) or {}


def document(rows):
    return yaml.safe_dump({'experience': {'next_level': rows}}, sort_keys=True)


class ExperienceRefreshTests(unittest.TestCase):
    def setUp(self):
        self.rows = {level: level * 500 for level in range(1, 100)}

    def source(self, rows=None, overlays=None):
        values = {'data/experience.yaml': document(self.rows if rows is None else rows)}
        values.update(overlays or {})
        return MemorySource(values)

    def test_yaml_level_keys_are_not_shifted_like_the_removed_sql_table(self):
        rows = exporter.experience_rows(self.source(), [])
        self.assertEqual(rows, self.rows)
        self.assertEqual(rows[1], 500)
        self.assertEqual(rows[99], 49500)

    def test_enabled_overlays_apply_in_init_order_and_retain_source_texts(self):
        first = 'modules/era/data/experience.yaml'
        second = 'modules/phoenix/data/experience.yaml'
        disabled = 'modules/unused/data/experience.yaml'
        source = self.source(overlays={
            first: document({1: 777, 75: 44444}),
            second: document({1: 999}),
            disabled: document({2: 123}),
        })
        roots = exporter.data_roots('era/data\nphoenix/data\n')
        rows = exporter.experience_rows(source, roots)
        self.assertEqual(rows[1], 999)
        self.assertEqual(rows[75], 44444)
        self.assertEqual(rows[2], self.rows[2])
        self.assertEqual(set(source.texts), {'data/experience.yaml', first, second})
        self.assertEqual(source.texts[second], document({1: 999}))

    def test_overlay_null_cannot_silently_remove_a_required_level(self):
        source = self.source(overlays={'modules/phoenix/data/experience.yaml': document({50: None})})
        with self.assertRaisesRegex(ValueError, 'every level'):
            exporter.experience_rows(source, ['modules/phoenix/data'])

    def test_missing_base_yaml_has_no_sql_fallback(self):
        source = MemorySource({'sql/exp_base.sql': 'old unused table'})
        with self.assertRaisesRegex(ValueError, 'missing data/experience.yaml'):
            exporter.experience_rows(source, [])

    def test_incomplete_or_out_of_range_levels_fail(self):
        for missing in (1, 50, 99):
            with self.subTest(missing=missing):
                rows = dict(self.rows)
                del rows[missing]
                with self.assertRaisesRegex(ValueError, 'every level'):
                    exporter.experience_rows(self.source(rows), [])
        for extra in (0, 100, '1'):
            with self.subTest(extra=extra):
                rows = dict(self.rows)
                rows[extra] = 500
                with self.assertRaisesRegex(ValueError, 'every level'):
                    exporter.experience_rows(self.source(rows), [])
        rows = dict(self.rows)
        del rows[1]
        rows[True] = 500
        with self.assertRaisesRegex(ValueError, 'every level'):
            exporter.experience_rows(self.source(rows), [])

    def test_thresholds_follow_the_native_unsigned_32_bit_type(self):
        for valid in (0, 4294967295):
            rows = dict(self.rows)
            rows[1] = valid
            self.assertEqual(exporter.experience_rows(self.source(rows), [])[1], valid)
        for invalid in (-1, 4294967296, 1.5, True, '500', None):
            with self.subTest(value=invalid):
                rows = dict(self.rows)
                rows[1] = invalid
                with self.assertRaisesRegex(ValueError, 'every level|unsigned 32-bit'):
                    exporter.experience_rows(self.source(rows), [])

    def test_malformed_yaml_and_wrong_table_shapes_fail(self):
        for text in ('experience: [', '[]', 'experience: []', 'experience: {next_level: []}'):
            with self.subTest(text=text):
                source = MemorySource({'data/experience.yaml': text})
                with self.assertRaises((ValueError, yaml.YAMLError)):
                    exporter.experience_rows(source, [])

    def test_current_loader_contract_guards_level_index_and_overlay_use(self):
        texts = {
            'src/map/utils/charutils.cpp': 'loadDataset<xi::data::datasets::experience::Dataset>()\nreturn experience().NextLevel[charlvl];',
            'src/map/data/datasets/experience/dataset.h': 'kDataPath{ "experience" }',
            'src/map/data/datasets/experience/dataset.cpp': 'yaml::read<YamlDocument>(text).experience\nexperience.NextLevel[level] = exp;\nsource.next_level.size() != kGrowthLevels - 1',
            'src/map/data/datasets/experience/yaml.h': 'std::map<uint8, uint32> next_level;',
            'src/map/data/datasets/stats/dataset.h': 'kGrowthLevels = 100;',
            'src/map/utils/dataset_loader.h': 'getDataModulePaths(dataPath, ".yaml")\nDataset::decode(loadMergedYaml(corePath, modules))',
        }
        exporter.validate_experience_loader(texts)
        for path in texts:
            with self.subTest(path=path):
                changed = dict(texts)
                changed[path] = ''
                with self.assertRaisesRegex(ValueError, 'loader contract changed'):
                    exporter.validate_experience_loader(changed)
        changed = dict(texts)
        changed['src/map/utils/charutils.cpp'] = texts['src/map/utils/charutils.cpp'].replace('[charlvl]', '[charlvl + 1]')
        with self.assertRaisesRegex(ValueError, 'loader contract changed'):
            exporter.validate_experience_loader(changed)

    def test_bundled_provenance_covers_yaml_and_loader_instead_of_removed_sql(self):
        rules = LuaRuntime(unpack_returned_tuples=True).execute((ROOT / 'momentum/data/phoenix_rules.lua').read_text())
        self.assertEqual(rules['source_ref'], exporter.PINNED_REF)
        hashes = dict(rules['source_sha256'].items())
        self.assertNotIn('sql/exp_base.sql', hashes)
        for path in ('data/experience.yaml', 'src/map/data/datasets/experience/dataset.cpp',
                     'src/map/data/datasets/experience/yaml.h', 'src/map/utils/dataset_loader.h',
                     'src/map/data/loader.h', 'src/map/data/yaml/merge.cpp'):
            self.assertEqual(len(hashes[path]), 64)
        tnl = dict(rules['tnl'].items())
        self.assertEqual(set(tnl), set(range(1, 100)))
        self.assertEqual(tnl[1], 500)
        self.assertEqual(tnl[50], 7800)
        self.assertEqual(tnl[75], 44000)
        self.assertEqual(tnl[99], 56000)


if __name__ == '__main__':
    unittest.main(verbosity=2)
