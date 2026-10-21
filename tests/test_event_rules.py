"""Check the event catalog and the limits on client-observed progress."""

from collections import Counter
from pathlib import Path
import sys
import unittest

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import export_events as exporter


def table(value):
    if hasattr(value, 'items'):
        return {key: table(item) for key, item in value.items()}
    return value


class EventRuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules = table(LuaRuntime(unpack_returned_tuples=True).execute(exporter.OUTPUT.read_text(encoding='utf8')))
        cls.battles = [battle for area in cls.rules['areas'].values() for battle in area['battles'].values()]

    def battle(self, slug):
        return next(battle for battle in self.battles if battle['source'].endswith('/' + slug + '.lua'))

    def test_catalog_only_includes_the_supported_event_types(self):
        self.assertEqual(Counter(battle['kind'] for battle in self.battles),
                         {'assault': 5, 'limbus': 14, 'bcnm': 43, 'ksnm': 18, 'enm': 18})
        self.assertEqual(set(self.rules['assault_missions']), {1, 11, 21, 31, 41})
        for battle in self.battles:
            self.assertGreater(battle['time_limit'], 0)
            self.assertGreater(battle['max_players'], 0)
            self.assertTrue(battle['name'])
            self.assertTrue(battle['objective']['text'])

    def test_all_battlefield_indices_are_zone_local_and_unique(self):
        ids = set()
        for zid, area in self.rules['areas'].items():
            for index, battle in area['battles'].items():
                self.assertEqual(battle['zone'], zid)
                if battle['kind'] != 'assault':
                    self.assertEqual(battle['index'], index)
                    self.assertNotIn(battle['id'], ids)
                    ids.add(battle['id'])

    def test_enm_acquisition_and_limbus_consumption_are_not_interchanged(self):
        cooldowns = self.rules['cooldowns']
        self.assertEqual(cooldowns['enm']['trigger'], 'key_item_obtained')
        self.assertEqual(cooldowns['enm']['duration'], 120 * 3600)
        self.assertEqual(cooldowns['limbus'], {'duration': 72000, 'trigger': 'battlefield_entry', 'scope': 'character'})
        self.assertEqual(cooldowns['dynamis'], {'duration': 259200, 'trigger': 'registration', 'scope': 'account'})
        self.assertEqual(set(self.rules['enm_groups']), {1, 2, 3, 4, 5, 6, 7, 8, 9, 100})
        self.assertEqual(self.battle('brothers')['enm_group'], self.battle('holy_cow')['enm_group'])
        self.assertNotEqual(self.battle('bionic_bug')['enm_group'], self.battle('pulling_the_strings')['enm_group'])
        self.assertEqual(self.battle('automaton_assault')['enm_group'], self.battle('pulling_the_strings')['enm_group'])

    def test_loaded_limbus_text_corrections_are_used(self):
        for zid in (37, 38):
            self.assertEqual(self.rules['areas'][zid]['messages']['ITEM_OBTAINED'], 6390)
            self.assertEqual(self.rules['areas'][zid]['messages']['KEYITEM_OBTAINED'], 6393)
        self.assertEqual(self.rules['areas'][37]['messages']['CHIP_TRADE_T'], 7030)

    def test_alternative_cards_are_not_presented_as_two_required_cards(self):
        cosmo = self.rules['key_items']['COSMO_CLEANSE']
        red = self.rules['key_items']['RED_CARD']
        black = self.rules['key_items']['BLACK_CARD']
        for slug in ('central_apollyon', 'cs_apollyon'):
            battle = self.battle(slug)
            self.assertEqual(set(battle['key_items'].values()), {cosmo})
            self.assertEqual(set(battle['key_item_options'][1].values()), {red, black})

    def test_random_objectives_and_reraises_do_not_become_false_remaining_counts(self):
        self.assertEqual(self.battle('undying_promise')['objective']['type'], 'unknown')
        self.assertEqual(self.battle('royale_ramble')['objective']['type'], 'unknown')
        self.assertEqual(self.battle('when_hell_freezes_over')['objective']['type'], 'waves')
        self.assertEqual(self.battle('when_hell_freezes_over')['objective']['required'], 4)
        self.assertNotIn('required', self.battle('nw_apollyon')['objective'])
        self.assertIn('reraises', self.battle('central_temenos_basement')['objective']['text'])

    def test_brittle_rocks_only_count_the_five_targetable_halves(self):
        objective = self.rules['assault_missions'][21]['objective']
        self.assertEqual(objective['required'], 5)
        self.assertEqual(set(objective['mob_ids']), {17035283, 17035285, 17035287, 17035289, 17035291})

    def test_limbus_route_names_do_not_copy_stale_source_comments(self):
        self.assertEqual(self.battle('central_temenos_2nd_floor')['name'], 'Central Temenos 2nd Floor')
        self.assertEqual(self.battle('central_temenos_basement')['name'], 'Central Temenos Basement')
        self.assertEqual(self.battle('nw_apollyon')['name'], 'NW Apollyon')
        self.assertEqual(self.battle('nw_apollyon')['floor_count'], 5)
        self.assertEqual(self.battle('temenos_western_tower')['floor_count'], 7)

    def test_objective_aliases_match_client_names_without_counting_other_avatars(self):
        for battle in self.battles:
            objective = battle['objective']
            if objective['type'] == 'kills':
                area = self.rules['areas'][battle['zone']]
                names = set(area['mobs'].values())
                for name in objective['mobs']:
                    self.assertIn(name, names, battle['name'])
        objective = self.battle('central_temenos_2nd_floor')['objective']
        self.assertEqual(len(objective['mob_ids']), 1)
        area = self.rules['areas'][37]
        self.assertGreater(sum(name == 'Mystic Avatar' for name in area['mobs'].values()), 1)
        for mob_id in objective['mob_ids']:
            self.assertEqual(area['mobs'][mob_id], 'Mystic Avatar')

    def test_orbs_only_use_era_seals_and_limbus_loot_has_categories(self):
        self.assertEqual(len(self.rules['orbs']), 9)
        self.assertEqual({orb['seal'] for orb in self.rules['orbs'].values()}, {'beastmen', 'kindred'})
        items = self.rules['items'].values()
        self.assertTrue(any(item['kind'] == 'coin' for item in items))
        self.assertTrue(any(item['kind'] == 'trophy' and 'Homam' in item['reward'] for item in items))
        self.assertTrue(any(item['kind'] == 'material' and item['job'] == 'WAR' for item in items))

    def test_shami_updates_use_the_normal_menu_and_receipt_contract(self):
        self.assertEqual(self.rules['npcs']['shami'], {
            'zone': 246, 'id': 17784905, 'event': 322, 'deposit_event': 321, 'empty_event': 23,
            'item_obtained': 6395, 'item_obtained_count': 6404, 'inventory_full': 6387,
        })
        self.assertEqual(self.rules['seal_items'], {'beastmen': 1126, 'kindred': 1127})
        self.assertEqual(self.rules['seal_retrieval'], {'beastmen': 2, 'kindred': 1})
        for path in ('scripts/zones/Port_Jeuno/npcs/Shami.lua', 'scripts/globals/seals.lua',
                     'scripts/globals/npc_util.lua', 'scripts/zones/Port_Jeuno/IDs.lua',
                     'src/map/packets/s2c/0x032_event.h', 'src/map/packets/c2s/0x05b_eventend.h'):
            self.assertIn(path, self.rules['source_sha256'])

    def test_source_hashes_cover_rules_overlays_and_cooldown_setters(self):
        self.assertEqual(self.rules['source_ref'], exporter.PINNED_REF)
        hashes = self.rules['source_sha256']
        for path in ('modules/init.txt', 'modules/phoenix/lua/custom/limbus_text_ids.lua',
                     'modules/phoenix/lua/quests/assault_limits.lua',
                     'modules/phoenix/lua/battlefields/up_in_arms_kraken_club.lua',
                     'modules/phoenix/data/limbus/zones/apollyon/mobs.yaml',
                     'scripts/globals/limbus.lua', 'scripts/globals/dynamis/dyna_lockout.lua',
                     'scripts/enum/msg.lua',
                     'scripts/zones/Uleguerand_Range/npcs/Zebada.lua'):
            self.assertIn(path, hashes)
            self.assertEqual(len(hashes[path]), 64)
        self.assertEqual(self.rules['basic_messages']['TIME_LEFT'], 202)

    def test_numeric_parser_fails_on_nonliteral_rules(self):
        self.assertEqual(exporter.integer('timeLimit = utils.minutes(15),', 'timeLimit'), 900)
        with self.assertRaises(ValueError):
            exporter.integer('timeLimit = getNewRule(),', 'timeLimit')
        with self.assertRaises(ValueError):
            exporter.enum_field('zoneId = xi.zone.MISSING,', 'zoneId', {}, 'xi.zone')


if __name__ == '__main__':
    unittest.main(verbosity=2)
