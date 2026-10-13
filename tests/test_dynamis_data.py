"""Keep the exported era data scoped to the rules the addon can observe."""

from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import export_dynamis as exporter


class DynamisExportTests(unittest.TestCase):
    def test_overlay_lists_replace_and_null_removes_old_spawns(self):
        base = {'templates': {'Orc': {'loot': {'drops': [{'item': 'old'}]}, 'level': 90}},
                'spawns': {1: {'template': 'Orc'}, 2: {'template': 'Orc'}}}
        patch = {'templates': {'Orc': {'loot': {'drops': [{'item': 'new'}]}}}, 'spawns': {2: None}}
        merged = exporter.merge_patch(base, patch)
        self.assertEqual(merged['templates']['Orc']['loot']['drops'], [{'item': 'new'}])
        self.assertEqual(merged['templates']['Orc']['level'], 90)
        self.assertEqual(set(merged['spawns']), {1})
        self.assertIn(2, base['spawns'])

    def test_unused_templates_do_not_add_modern_items(self):
        document = {
            'templates': {
                'Era': {'loot': {'drops': [{'one_of': ['one_byne_bill', 'warriors_lorica']}] }},
                'Modern': {'loot': {'drops': [{'item': 'forgotten_touch'}]}},
            },
            'spawns': {1: {'template': 'Era'}},
        }
        self.assertEqual(exporter.loot_names(document), {'one_byne_bill', 'warriors_lorica'})

    def test_spawn_loot_override_replaces_template_loot(self):
        document = {
            'templates': {'Era': {'loot': {'drops': [{'item': 'one_byne_bill'}]}}},
            'spawns': {1: {'template': 'Era', 'loot': {'drops': [{'item': 'ordelle_bronzepiece'}]}}},
        }
        self.assertEqual(exporter.loot_names(document), {'ordelle_bronzepiece'})

    def test_missing_used_template_is_an_error(self):
        with self.assertRaisesRegex(ValueError, 'no template'):
            exporter.loot_names({'templates': {}, 'spawns': {1: {'template': 'Missing'}}})

    def test_module_roots_preserve_order_and_do_not_recurse(self):
        self.assertEqual(exporter.data_roots(
            '# skipped\nera/lua\nera/data/\nphoenix/data\nphoenix/data/dynazones/\nphoenix/data\nbare\n'),
            ['modules/era/data', 'modules/phoenix/data', 'modules/phoenix/data/dynazones', 'modules/bare/data'])

    def test_source_table_parser_ignores_commented_rules_and_quoted_braces(self):
        text = "-- rules = { fake = 9 }\nrules = { help = 'Keep } -- this', row = { 1, 2 } }\nother = {}"
        self.assertEqual(exporter.table_after(text, 'rules'), " help = 'Keep } -- this', row = { 1, 2 } ")
        with self.assertRaises(ValueError):
            exporter.table_after('-- rules = {}', 'rules')

    def test_currency_units_and_job_categories(self):
        self.assertEqual(exporter.item_kind('one_byne_bill'), {'kind': 'currency', 'family': 'byne', 'value': 1})
        self.assertEqual(exporter.item_kind('montiont_silverpiece'), {'kind': 'currency', 'family': 'bronze', 'value': 100})
        self.assertEqual(exporter.item_kind('warriors_lorica'), {'kind': 'af2', 'job': 'WAR'})
        self.assertEqual(exporter.item_kind('warriors_lorica_-1'), {'kind': 'armor_minus1', 'job': 'WAR'})
        self.assertEqual(exporter.item_kind('saotome_koshi-ate'), {'kind': 'accessory', 'job': 'SAM'})
        self.assertEqual(exporter.item_kind('koga_sarashi'), {'kind': 'accessory', 'job': 'NIN'})
        self.assertEqual(exporter.item_kind('warriors_stone'), {'kind': 'accessory', 'job': 'WAR'})
        self.assertEqual(exporter.item_kind('shard_of_necropsyche'), {'kind': 'necropsyche'})
        self.assertEqual(exporter.item_kind('ihintanto'), {'kind': 'weapon'})
        self.assertEqual(exporter.item_kind('ito'), {'kind': 'weapon'})
        self.assertEqual(exporter.item_kind('shadow_ring'), {'kind': 'accessory'})

    def test_prerequisite_rows_use_code_not_stale_comments(self):
        text = """
            xi.dynamis.deathVarByMob[zoneID] = { [xi.qufim.mobs.ANTAEUS] = '[DYNA]Boss' }
            xi.dynamis.spawnCheck[zoneID] = {
                -- Requires three kills. This comment is deliberately wrong.
                { requiredVars = { '[DYNA]Boss' }, spawn = {}, spawnedVar = '[DYNA]BossWaveSpawned' }
            }
        """
        result = exporter.objectives(text, 'qufim', {'ANTAEUS': 16945355}, {16945355: 'Antaeus'})
        self.assertEqual(result[0]['mobs'], [16945355])
        self.assertEqual(result[0]['id'], 'BossWaveSpawned')
        with self.assertRaisesRegex(ValueError, 'prerequisite rows changed'):
            exporter.objectives(text, 'sandy', {'ANTAEUS': 16945355}, {})

    def test_lua_renderer_escapes_player_facing_strings(self):
        self.assertEqual(exporter.lua("Warrior's\n\\"), "'Warrior\\'s\\n\\\\'")
        self.assertEqual(exporter.lua({2: 'b', 1: 'a'}), "{\n    [1] = 'a',\n    [2] = 'b',\n}")


class ExportedDynamisDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = exporter.OUTPUT.read_text(encoding='utf8')
        cls.zones = exporter.table_after(cls.text, 'zones')
        cls.items = exporter.table_after(cls.text, 'items')

    def zone(self, zone_id):
        return exporter.table_after(self.zones, r'\[' + str(zone_id) + r'\]')

    def test_only_ten_original_zones_and_no_global_remaining_count(self):
        names = re.findall(r"^\s*name = '(Dynamis-[^']+)'", self.zones, re.M)
        self.assertEqual(len(names), 10)
        self.assertEqual({value for value in re.findall(r'^\s*\[(\d+)\] = \{', self.zones, re.M) if int(value) < 300},
                         {'39', '40', '41', '42', '134', '135', '185', '186', '187', '188'})
        self.assertNotIn('remaining_mobs', self.text)
        self.assertNotIn('total_mobs', self.text)

    def test_fixed_constants_come_from_current_era_rules(self):
        self.assertIn("source_ref = '" + exporter.PINNED_REF + "'", self.text)
        self.assertEqual(exporter.number(self.text, 'hourglass_id'), 4237)
        self.assertEqual(exporter.number(self.text, 'lockout_seconds'), 259200)
        self.assertEqual(exporter.number(self.text, 'reentry_weakness_seconds'), 600)
        self.assertEqual(exporter.number(exporter.table_after(self.text, 'status_effects'), 'subjob_locked'), 157)
        self.assertEqual(exporter.number(self.zone(42), 'starting_seconds'), 900)
        self.assertEqual(exporter.number(self.zone(188), 'starting_seconds'), 3600)

    def test_tavnazia_qm_time_is_separate_from_eye_deaths(self):
        tav = self.zone(42)
        extensions = exporter.table_after(tav, 'extensions')
        npcs = exporter.table_after(tav, 'extension_npcs')
        self.assertEqual(dict(re.findall(r'\[(\d+)\] = (\d+)', extensions)), {'16949249': '15', '16949255': '30'})
        self.assertEqual(dict(re.findall(r'\[(\d+)\] = (\d+)', npcs)), {'16949654': '30', '16949655': '30'})
        self.assertIn('Check it to receive the time', tav)
        self.assertIn('bosses = {  }', tav)

    def test_loot_categories_include_all_era_jobs_and_exclude_unused_modern_loot(self):
        kinds = {kind: len(re.findall(r"kind = '" + kind + "'", self.items)) for kind in
                 ('af2', 'armor_minus1', 'accessory', 'currency', 'weapon', 'attestation', 'fragment', 'necropsyche', 'hydra')}
        self.assertEqual(kinds, {'af2': 90, 'armor_minus1': 90, 'accessory': 20, 'currency': 6,
                                'weapon': 16, 'attestation': 16, 'fragment': 16, 'necropsyche': 1, 'hydra': 20})
        jobs = set(re.findall(r"job = '([^']+)'", self.items))
        self.assertEqual(jobs, set(exporter.JOBS.values()))
        for modern in ('Forgotten', 'Umbral Marrow', 'Ten Thousand', 'Portus', 'Alucinor'):
            self.assertNotIn(modern, self.items)

    def test_normal_mobs_are_in_observed_death_id_lookup(self):
        names = exporter.table_after(self.zone(188), 'mob_names')
        self.assertIn("[17547266] = 'Vanguard Smithy'", names)
        self.assertIn("[17547265] = 'Goblin Replica'", names)
        self.assertIn("[17547627] = 'Goblin Golem'", names)

    def test_buburimu_has_all_weakening_mobs_and_source_hashes(self):
        weakening = exporter.table_after(self.zone(40), 'weakening')
        self.assertEqual(len(re.findall(r'^\s*\[\d+\] = \{', weakening, re.M)), 25)
        self.assertIn("name = 'Astral Flow'", weakening)
        self.assertIn("name = 'Voidsong'", weakening)
        hashes = exporter.table_after(self.text, 'source_sha256')
        self.assertIn('modules/init.txt', hashes)
        self.assertIn('modules/phoenix/data/dynazones/zones/dynamis_jeuno/mobs.yaml', hashes)


if __name__ == '__main__':
    unittest.main(verbosity=2)
