"""Export the era Dynamis rules and placed-mob loot from a pinned Phoenix tree."""

import argparse
import copy
import hashlib
from pathlib import Path
import re
import subprocess

import yaml


PINNED_REF = '071c401048bdb97bcbe12ad93651574fcf867407'
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'momentum/data/dynamis_rules.lua'
ZONES = (
    ('san_doria', 'San_dOria', 'sandy', 'OVERLORDS_TOMBSTONE'),
    ('bastok', 'Bastok', 'bastok', 'GUDHA_EFFIGY'),
    ('windurst', 'Windurst', 'windurst', 'TZEE_XICU_IDOL'),
    ('jeuno', 'Jeuno', 'jeuno', 'GOBLIN_GOLEM'),
    ('beaucedine', 'Beaucedine', 'beauc', 'ANGRA_MAINYU'),
    ('xarcabard', 'Xarcabard', 'xarc', 'DYNAMIS_LORD'),
    ('valkurm', 'Valkurm', 'valk', 'CIRRATE_CHRISTELLE'),
    ('buburimu', 'Buburimu', 'bubu', 'APOCALYPTIC_BEAST'),
    ('qufim', 'Qufim', 'qufim', 'ANTAEUS'),
    ('tavnazia', 'Tavnazia', 'tav', None),
)
MOB_FILE = {'beauc': 'beaucedine', 'xarc': 'xarcabard', 'bubu': 'buburimu'}
JOBS = {
    'warriors': 'WAR', 'melee': 'MNK', 'clerics': 'WHM', 'sorcerers': 'BLM',
    'duelists': 'RDM', 'assassins': 'THF', 'valor': 'PLD', 'abyss': 'DRK',
    'monster': 'BST', 'bards': 'BRD', 'scouts': 'RNG', 'saotome': 'SAM',
    'koga': 'NIN', 'wyrm': 'DRG', 'summoners': 'SMN', 'mirage': 'BLU',
    'commodore': 'COR', 'pantin': 'PUP',
}
CURRENCY = {
    'one_byne_bill': ('byne', 1), 'one_hundred_byne_bill': ('byne', 100),
    'tukuku_whiteshell': ('shell', 1), 'lungo-nango_jadeshell': ('shell', 100),
    'ordelle_bronzepiece': ('bronze', 1), 'montiont_silverpiece': ('bronze', 100),
}
ACCESSORY_SUFFIXES = ('belt', 'cape', 'mantle', 'sash', 'torque', 'earring', 'stone', 'sarashi', 'koshi-ate')
ENTRY_FOLDERS = {
    'SOUTHERN_SAN_DORIA': 'Southern_San_dOria', 'BASTOK_MINES': 'Bastok_Mines',
    'WINDURST_WALLS': 'Windurst_Walls', 'RULUDE_GARDENS': 'RuLude_Gardens',
    'BEAUCEDINE_GLACIER': 'Beaucedine_Glacier', 'XARCABARD': 'Xarcabard',
    'VALKURM_DUNES': 'Valkurm_Dunes', 'BUBURIMU_PENINSULA': 'Buburimu_Peninsula',
    'QUFIM_ISLAND': 'Qufim_Island', 'TAVNAZIAN_SAFEHOLD': 'Tavnazian_Safehold',
}
OBJECTIVE_NAMES = {
    'sandy': ['Wyrmgnasher group', 'Reapertongue group', "Overlord's Tombstone", 'Voidstreaker group', 'After the boss'],
    'bastok': ["Gu'Dha Effigy", 'After the boss'],
    'windurst': ['Tzee Xicu Idol', 'After the boss', 'Wuu Qoho group', 'Xoo Kaza group', 'Haa Pevi group', "Heavens Tower", 'Manifest Icon group'],
    'jeuno': ['Replica 73 group', 'Fountain group', 'Statue 44 group', 'Goblin Golem group', 'After the boss'],
    'beauc': ['Attestation NMs', 'Vanguard Eye 147'],
    'xarc': ['Vanguard Eye 43', 'Vanguard Eye 60', 'Vanguard Eye 150', 'Dynamis Lord', 'Demon NM group'],
    'valk': ['After the boss'], 'bubu': ['After the boss'], 'qufim': ['After the boss'], 'tav': [],
}
OBJECTIVE_FLAGS = {
    'sandy': ['WyrmgnasherWaveSpawned', 'ReapertongueWaveSpawned', 'MegaBossSpawned', 'VoidstreakerWaveSpawned', 'BossWaveSpawned'],
    'bastok': ['MegaBossSpawned', 'Wave2Spawned'],
    'windurst': ['MegaBossSpawned', 'Wave2Spawned', 'Wave3Spawned', 'Wave4Spawned', 'Wave5Spawned', 'Wave6Spawned', 'Wave7Spawned'],
    'jeuno': ['Wave6Spawned', 'Wave2Spawned', 'Wave3Spawned', 'Wave4Spawned', 'Wave5Spawned'],
    'beauc': ['Wave2Spawned', 'Eye147Spawned'],
    'xarc': ['43Spawned', '60Spawned', '150Spawned', 'DynamisLordSpawned', 'Wave2Spawned'],
    'valk': ['Wave2Spawned'], 'bubu': ['BossWaveSpawned'], 'qufim': ['BossWaveSpawned'], 'tav': [],
}


class Source:
    def __init__(self, repo, ref):
        self.repo = Path(repo)
        self.ref = subprocess.check_output(
            ['git', '-C', str(repo), 'rev-parse', ref + '^{commit}'], text=True).strip()
        self.paths = set(subprocess.check_output(
            ['git', '-C', str(repo), 'ls-tree', '-r', '--name-only', self.ref], text=True).splitlines())
        self.texts = {}

    def read(self, path):
        if path not in self.texts:
            self.texts[path] = subprocess.check_output(
                ['git', '-C', str(self.repo), 'show', self.ref + ':' + path]
            ).decode('utf8').replace('\r\n', '\n')
        return self.texts[path]

    def yaml(self, path):
        return yaml.safe_load(self.read(path)) or {}


def merge_patch(target, patch):
    """Apply Phoenix's map merge, list replacement, and null deletion rules."""
    if not isinstance(patch, dict):
        return copy.deepcopy(patch)
    result = copy.deepcopy(target) if isinstance(target, dict) else {}
    for key, value in patch.items():
        if value is None:
            result.pop(key, None)
        else:
            result[key] = merge_patch(result.get(key), value)
    return result


def data_roots(init):
    roots = []
    for line in init.splitlines():
        entry = line.split('#', 1)[0].strip().rstrip('/')
        parts = entry.split('/')
        if not entry or ('data' not in parts and len(parts) != 1):
            continue
        root = 'modules/' + entry + ('' if 'data' in parts else '/data')
        if root not in roots:
            roots.append(root)
    return roots


def merged_dataset(source, roots, name):
    result = source.yaml('data/' + name + '.yaml')
    for root in roots:
        path = root + '/' + name + '.yaml'
        if path in source.paths:
            result = merge_patch(result, source.yaml(path))
    return result


def without_comments(text):
    # Keep quoted strings intact, including the -- in player-facing text.
    pattern = r"('(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")|--\[\[.*?\]\]|--[^\n]*"
    return re.sub(pattern, lambda match: match.group(1) or '', text, flags=re.S)


def table_after(text, marker):
    clean = without_comments(text)
    match = re.search(marker + r'\s*=\s*\{', clean)
    if not match:
        raise ValueError('Missing source table: ' + marker)
    start = match.end() - 1
    depth, quote, escaped = 0, None, False
    for pos in range(start, len(clean)):
        char = clean[pos]
        if quote:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == quote:
                quote = None
        elif char in "'\"":
            quote = char
        elif char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return clean[start + 1:pos]
    raise ValueError('Unclosed source table: ' + marker)


def number(text, key):
    match = re.search(r'\b' + re.escape(key) + r'\s*=\s*(\d+)\b', text)
    if not match:
        raise ValueError('Missing numeric source field: ' + key)
    return int(match.group(1))


def pretty_name(name):
    # Client item resources supply their exact localized spelling in game.
    return name.replace('_', ' ').replace(' minus1', ' -1').title()


def item_name(name):
    result = pretty_name(name)
    for prefix in ('Warriors', 'Clerics', 'Sorcerers', 'Duelists', 'Assassins', 'Bards', 'Scouts', 'Summoners'):
        if result.startswith(prefix + ' '):
            result = prefix[:-1] + "'s" + result[len(prefix):]
    return result


def item_kind(name):
    if name in CURRENCY:
        family, value = CURRENCY[name]
        return {'kind': 'currency', 'family': family, 'value': value}
    for prefix, job in JOBS.items():
        if name.startswith(prefix + '_'):
            kind = 'armor_minus1' if name.endswith(('_minus1', '_-1')) else (
                'accessory' if name.endswith(ACCESSORY_SUFFIXES) else 'af2')
            return {'kind': kind, 'job': job}
    if name.startswith('hydra_'):
        return {'kind': 'hydra'}
    if name.startswith('attestation_of_'):
        return {'kind': 'attestation'}
    if name.endswith('_fragment'):
        return {'kind': 'fragment'}
    if name in ('necropsyche', 'shard_of_necropsyche'):
        return {'kind': 'necropsyche'}
    if name.startswith('relic_') or name in ('ihintanto', 'ito'):
        return {'kind': 'weapon'}
    if name in ('shadow_mantle', 'shadow_ring'):
        return {'kind': 'accessory'}
    return {'kind': 'material'}


def loot_names(document):
    """Only placed spawns contribute loot; unused modern templates do not."""
    names = set()

    def collect(value):
        if isinstance(value, dict):
            if isinstance(value.get('item'), str):
                names.add(value['item'])
            if isinstance(value.get('one_of'), list):
                names.update(x for x in value['one_of'] if isinstance(x, str))
            for child in value.values():
                collect(child)
        elif isinstance(value, list):
            for child in value:
                collect(child)

    for spawn in document.get('spawns', {}).values():
        if not isinstance(spawn, dict):
            continue
        template = document.get('templates', {}).get(spawn.get('template'))
        if template is None:
            raise ValueError('Placed mob has no template: ' + str(spawn.get('template')))
        effective = merge_patch(template, {key: value for key, value in spawn.items() if key != 'template'})
        collect(effective.get('loot', {}))
    return names


def parse_mobs(text, prefix):
    body = table_after(text, r'xi\.' + prefix + r'\.mobs')
    return {name: int(value) for name, value in re.findall(r'\b([A-Z][A-Z0-9_]*)\s*=\s*(\d+)', body)}


def resolve_mob(token, mobs):
    token = token.strip()
    if token.isdigit():
        return int(token)
    key = token.rsplit('.', 1)[-1]
    if key not in mobs:
        raise ValueError('Unknown mob constant: ' + token)
    return mobs[key]


def objectives(text, prefix, mobs, mob_names):
    if prefix == 'tav':
        return []
    deaths = table_after(text, r'xi\.dynamis\.deathVarByMob\[zoneID\]')
    by_var = {var: resolve_mob(token, mobs) for token, var in re.findall(
        r"\[([^\]]+)\]\s*=\s*'([^']+)'", deaths)}
    checks = table_after(text, r'xi\.dynamis\.spawnCheck\[zoneID\]')
    rows = re.findall(r"requiredVars\s*=\s*\{([^}]+)\}.*?spawnedVar\s*=\s*'([^']+)'", checks, re.S)
    if [flag.removeprefix('[DYNA]') for _, flag in rows] != OBJECTIVE_FLAGS[prefix]:
        raise ValueError('Spawn prerequisite rows changed in ' + prefix)
    result = []
    for (required, flag), name in zip(rows, OBJECTIVE_NAMES[prefix]):
        ids = [by_var[var] for var in re.findall(r"'([^']+)'", required)]
        targets = ', '.join(mob_names.get(mid, str(mid)) for mid in ids)
        result.append({'id': flag.removeprefix('[DYNA]'), 'name': name,
                       'help': 'Defeat ' + targets + ' to unlock this group. Only kills seen during this run are checked off.',
                       'mobs': ids})
    return result


def build(source):
    init = source.read('modules/init.txt')
    roots = data_roots(init)
    if not re.search(r'^phoenix/dynamis/lua/?\s*$', init, re.M):
        raise ValueError('Phoenix era Dynamis is not enabled.')
    if 'modules/phoenix/data/dynazones' not in roots:
        raise ValueError('Phoenix era Dynamis spawn data is not enabled.')
    zone_ids = source.yaml('data/enums/zone.yaml')['values']
    key_items = source.yaml('data/enums/key_item.yaml')['values']
    config = source.read('scripts/globals/dynamis/zone_config.lua')
    settings = source.read('scripts/globals/dynamis/settings_era.lua')
    overrides = source.read('modules/phoenix/dynamis/lua/dynamis_overrides.lua')
    enabled = table_after(overrides, r'local dynamisZones')
    configured_zones = re.findall(r'xi\.zone\.DYNAMIS_([A-Z_]+)', enabled)
    if set(configured_zones) != {zone.upper() for zone, _, _, _ in ZONES}:
        raise ValueError('The enabled era Dynamis zones changed.')
    entry_table = table_after(config, r'xi\.dynamis\.entryInfoEra')
    zone_table = table_after(config, r'xi\.dynamis\.dynaInfoEra')
    item_sql = source.read('sql/item_basic.sql')
    item_ids = {name: int(item_id) for item_id, name in re.findall(
        r"INSERT INTO `item_basic` VALUES \((\d+),\d+,'([^']+)'", item_sql)}
    if item_ids.get('perpetual_hourglass') != 4237:
        raise ValueError('The Perpetual Hourglass item ID changed.')
    zones, item_names = {}, set()
    all_mobs = {}
    for key, folder, prefix, boss in ZONES:
        zid = zone_ids['dynamis_' + key]
        data = merged_dataset(source, roots, 'zones/dynamis_' + key + '/mobs')
        item_names.update(loot_names(data))
        mob_names = {int(mid): pretty_name(spawn['template']) for mid, spawn in data['spawns'].items()}
        filename = MOB_FILE.get(prefix, prefix)
        text = source.read('scripts/globals/dynamis/mobs/dynamis_mobs_' + filename + '.lua')
        mobs = parse_mobs(text, prefix)
        all_mobs[prefix] = mobs
        zone_config = table_after(zone_table, r'\[xi\.zone\.DYNAMIS_' + key.upper() + r'\]')
        ki_name = re.search(r'winKI\s*=\s*xi\.keyItem\.([A-Z_]+)', zone_config).group(1).lower()
        entry_match = re.search(r'\[xi\.zone\.([A-Z_]+)\]\s*=\s*\{[^}]*?dynaZone\s*=\s*xi\.zone\.DYNAMIS_' + key.upper() + r'\b', entry_table, re.S)
        if not entry_match:
            raise ValueError('Missing entry zone for ' + key)
        entry_key = entry_match.group(1)
        entry = table_after(entry_table, r'\[xi\.zone\.' + entry_key + r'\]')
        entry_ids = source.read('scripts/zones/' + ENTRY_FOLDERS[entry_key] + '/IDs.lua')
        entry_lookup = table_after(table_after(config, r'xi\.dynamis\.dynaIDLookup'), r'\[xi\.zone\.' + entry_key + r'\]')
        registration = re.search(r'INFORMATION_RECORDED\s*=\s*zones\[xi\.zone\.' + entry_key + r'\]\.text\.YOU_CANNOT_ENTER_DYNAMIS\s*-\s*(\d+)', entry_lookup)
        if not registration:
            raise ValueError('Registration message mapping changed for ' + entry_key)
        ids = source.read('scripts/zones/Dynamis-' + folder + '/IDs.lua')
        extensions = table_after(text, r'xi\.dynamis\.timeExtension\[zoneID\]')
        extension_mobs = {resolve_mob(token, mobs): int(minutes) for token, minutes in re.findall(
            r'\[([^\]]+)\]\s*=\s*(\d+)', extensions)}
        eye_table = table_after(text, r'xi\.dynamis\.eyeColor\[zoneID\]')
        statues = {int(mid): ('hp' if color == 'BLUE' else 'mp') for mid, color in re.findall(
            r'\[(\d+)\]\s*=\s*xi\.dynamis\.eye\.(BLUE|GREEN)', eye_table)}
        objectives_list = objectives(text, prefix, mobs, mob_names)
        bosses = [mobs[boss]] if boss in mobs else []
        if boss and not bosses:
            matches = [mid for mid, spawn in data['spawns'].items() if spawn['template'].upper() == boss]
            if len(matches) != 1:
                raise ValueError('Cannot resolve zone boss: ' + str(boss))
            bosses = matches
        zone = {
            'name': 'Dynamis-' + folder, 'short_name': "San d'Oria" if key == 'san_doria' else folder,
            'starting_seconds': number(settings, 'TAVNAZIA_TIME_LIMIT' if key == 'tavnazia' else 'DEFAULT_TIME_LIMIT'),
            'clear_ki': key_items[ki_name], 'clear_npc': number(zone_config, 'winQM'),
            'extension_message': number(ids, 'DYNAMIS_TIME_EXTEND'),
            'entry_message': number(ids, 'DYNAMIS_TIME_BEGIN'),
            'time_update_messages': [number(ids, 'DYNAMIS_TIME_UPDATE_1'), number(ids, 'DYNAMIS_TIME_UPDATE_2')],
            'expired_message': number(ids, 'DYNAMIS_TIME_EXPIRED'),
            'entry_zones': [zone_ids[entry_key.lower()]],
            'registration_event': number(entry, 'csRegisterGlass'),
            'registration_message': number(entry_ids, 'YOU_CANNOT_ENTER_DYNAMIS') - int(registration.group(1)),
            'capacity': number(entry, 'maxCapacity'),
            'dreamlands': key in ('valkurm', 'buburimu', 'qufim', 'tavnazia'),
            'extensions': extension_mobs, 'extension_npcs': {}, 'objectives': objectives_list,
            'bosses': bosses, 'mob_names': {}, 'weakening': {}, 'statues': statues,
        }
        if key == 'valkurm':
            zone['objectives'].insert(0, {
                'id': 'subjobs', 'name': 'Restore subjobs',
                'help': 'Defeat all three Nightmare Flies. Your subjob status confirms when the restriction is gone.',
                'mobs': [mobs['NIGHTMARE_FLY_' + str(i)] for i in (1, 2, 3)],
            })
        if key in ('buburimu', 'qufim'):
            zone['info'] = 'Find and check the subjob ???. Its location is chosen when the run starts.'
        if key == 'tavnazia':
            tav = source.read('scripts/globals/dynamis/zonemechs/tavnazia.lua')
            for required in ('killedCount == 1 and math.randomInt(1, 2) == 1', 'killedCount == 2', 'xi.dynamis.addMinutesToDynamis(zone, 30)'):
                if required not in tav:
                    raise ValueError('Tavnazia extension rules changed: ' + required)
            npc_ids = [int(value) for value in re.search(r'timeExtensions\s*=\s*\{([^}]+)\}', zone_config).group(1).split(',')]
            zone['extension_npcs'] = {nid: 30 for nid in npc_ids}
            zone['info'] = 'The extension ??? may appear after the first eye and always appears after both. Check it to receive the time and spawn its group.'
            zone['objectives'] = [
                {'id': 'subjobs', 'name': 'Restore subjobs', 'help': 'Defeat the Nightmare Worm and Nightmare Antlion. Their spawn positions are chosen for the run.',
                 'mobs': [mobs['NIGHTMARE_WORM'], mobs['NIGHTMARE_ANTLION']]},
                {'id': 'extension1', 'name': 'First extension ???', 'help': zone['info'],
                 'mobs': [mobs['VANGUARD_EYE_9'], mobs['VANGUARD_EYE_15']]},
                {'id': 'extension2', 'name': 'Second extension ???', 'help': zone['info'],
                 'mobs': [mobs['VANGUARD_EYE_67'], mobs['VANGUARD_EYE_75']]},
            ]
        # This is an ID lookup for observed deaths, not a live remaining-mob count.
        zone['mob_names'] = dict(sorted(mob_names.items()))
        zones[zid] = zone
    bubu = source.read('scripts/globals/dynamis/zonemechs/buburimu.lua')
    bubu_file = source.read('scripts/globals/dynamis/mobs/dynamis_mobs_buburimu.lua')
    deaths = table_after(bubu_file, r'xi\.dynamis\.deathVarByMob\[zoneID\]')
    by_var = {var: resolve_mob(token, all_mobs['bubu']) for token, var in re.findall(r"\[([^\]]+)\]\s*=\s*'([^']+)'", deaths)}
    zone = zones[zone_ids['dynamis_buburimu']]
    abilities = table_after(bubu, r'local apocAbilities')
    for var, skill in re.findall(r"\{\s*'([^']+)'\s*,\s*xi\.mobSkill\.([A-Z0-9_]+)", abilities):
        name = pretty_name(re.sub(r'_1$', '', skill)).replace('Ees Goblin', 'Eagle Eye Shot')
        mid = by_var[var]
        zone['weakening'][mid] = {'name': name, 'help': 'Defeat this NM to stop Apocalyptic Beast from using ' + name + '.'}
    # These labels are the ten numeric skill IDs used by the pinned ability picker.
    skill_names = ('Flame Breath', 'Poison Breath', 'Wind Breath', 'Body Slam', 'Heavy Stomp', 'Chaos Blade', 'Petro Eyes', 'Voidsong', 'Thornsong', 'Lodesong')
    skill_sql = source.read('sql/mob_skills.sql')
    sql_skill_names = {int(sid): name for sid, name in re.findall(
        r"INSERT INTO `mob_skills` VALUES \((\d+),\d+,'([^']+)'", skill_sql)}
    lockouts = table_after(bubu, r'local apocWeaponskillLockouts')
    rows = re.findall(r"\{\s*(xi\.bubu\.mobs\.[A-Z_]+)\s*,\s*'([^']+)'\s*,\s*(\d+)", lockouts)
    if [int(row[2]) for row in rows] != list(range(642, 652)):
        raise ValueError('Buburimu dragon weapon skills changed.')
    for (token, _, skill_id_text), name in zip(rows, skill_names):
        skill_id = int(skill_id_text)
        source_name = sql_skill_names[skill_id].replace('_dragon_1', '')
        if pretty_name(source_name) != name:
            raise ValueError('Buburimu weapon skill name changed: ' + str(skill_id))
        mid = resolve_mob(token, all_mobs['bubu'])
        zone['weakening'][mid] = {'name': name, 'help': 'Defeat this dragon to stop Apocalyptic Beast from using ' + name + '.'}
    for key, mid in all_mobs['bubu'].items():
        if mid in zone['weakening']:
            zone['mob_names'][mid] = pretty_name(key)
    if len(zone['weakening']) != 25:
        raise ValueError('Expected 25 Apocalyptic Beast weakening NMs.')
    items = {}
    for name in sorted(item_names):
        if name not in item_ids:
            raise ValueError('No item ID for placed-mob loot: ' + name)
        items[item_ids[name]] = {'name': item_name(name), **item_kind(name)}
    effects = merged_dataset(source, roots, 'status_effects')['status_effects']
    result = {
        'source_ref': source.ref, 'hourglass_id': item_ids['perpetual_hourglass'],
        'lockout_seconds': number(settings, 'REENTRY_DAYS') * 86400,
        'reentry_weakness_seconds': number(settings, 'REENTRY_WEAKNESS'),
        'status_effects': {'weakness': effects['weakness']['id'], 'subjob_locked': effects['sj_restriction']['id']},
        'zones': zones, 'items': items,
    }
    result['source_sha256'] = {path: hashlib.sha256(text.encode('utf8')).hexdigest() for path, text in sorted(source.texts.items())}
    return result


def lua(value, indent=0):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"
    if isinstance(value, list):
        if all(isinstance(v, (int, str)) for v in value):
            return '{ ' + ', '.join(lua(v) for v in value) + ' }'
        return '{\n' + ''.join(' ' * (indent + 4) + lua(v, indent + 4) + ',\n' for v in value) + ' ' * indent + '}'
    if isinstance(value, dict):
        if not value:
            return '{}'
        keys = sorted(value) if all(isinstance(k, int) for k in value) else value.keys()
        rows = []
        for key in keys:
            label = key if isinstance(key, str) and re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_]*', key) else '[' + lua(key) + ']'
            rows.append(' ' * (indent + 4) + str(label) + ' = ' + lua(value[key], indent + 4) + ',\n')
        return '{\n' + ''.join(rows) + ' ' * indent + '}'
    raise TypeError(type(value))


def render(repo, ref=PINNED_REF):
    return '-- Phoenix era Dynamis. Refresh with tools/export_dynamis.py.\nreturn ' + lua(build(Source(repo, ref))) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='Phoenix checkout; reads Git objects only.')
    parser.add_argument('--ref', default=PINNED_REF)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    output = render(args.source, args.ref)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding='utf8') != output:
            raise SystemExit('Dynamis data is out of date. Run the exporter without --check.')
        print('Phoenix Dynamis data matches the pinned source.')
    else:
        OUTPUT.write_text(output, encoding='utf8', newline='\n')
        print('Exported Phoenix Dynamis data to momentum/data/dynamis_rules.lua.')


if __name__ == '__main__':
    main()
