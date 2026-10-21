"""Export client-observable event rules from a pinned Phoenix Git revision."""

import argparse
from collections import Counter
import hashlib
from pathlib import Path
import re

from export_dynamis import Source, data_roots, lua, merge_patch, table_after, without_comments


PINNED_REF = '11c6ee57720a8c6fd79c0fd46ff38ea8e074bf5e'
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'momentum/data/event_rules.lua'
ASSAULTS = ('leujaoam_cleansing', 'imperial_agent_rescue', 'excavation_duty', 'seagull_grounded', 'golden_salvage')
ENM_KEYS = {
    'CENSER_OF_ABANDONMENT': (1, 'Spire of Holla', '[ENM]abandonmentTimer'),
    'CENSER_OF_ANTIPATHY': (2, 'Spire of Dem', '[ENM]antipathyTimer'),
    'CENSER_OF_ANIMUS': (3, 'Spire of Mea', '[ENM]animusTimer'),
    'CENSER_OF_ACRIMONY': (4, 'Spire of Vahzl', '[ENM]acrimonyTimer'),
    'MONARCH_BEARD': (5, 'Monarch Linn', '[ENM]MonarchBeard'),
    'ASTRAL_COVENANT': (6, 'The Shrouded Maw', '[ENM]AstralCovenant'),
    'SHAFT_2716_OPERATING_LEVER': (7, 'Mine Shaft 2716 lever', '[ENM]OperatingLever'),
    'ZEPHYR_FAN': (8, 'Bearclaw Pinnacle', '[ENM]ZephyrFan'),
    'MIASMA_FILTER': (9, 'Boneyard Gully', '[ENM]MiasmaFilter'),
    'SHAFT_GATE_OPERATING_DIAL': (100, 'Mine Shaft 2716 dial', '[ENM]GateDial'),
}


def numbers(text):
    return {name: int(value) for name, value in re.findall(r'\b([A-Z][A-Z0-9_]*)\s*=\s*(\d+)\b', without_comments(text))}


def field(text, name, required=True):
    found = re.search(r'\b' + name + r'\s*=\s*([^,\n]+)', text)
    if found:
        return found.group(1).strip()
    if required:
        raise ValueError('Missing field ' + name)
    return None


def integer(text, name, default=None):
    value = field(text, name, default is None)
    if value is None:
        return default
    found = re.fullmatch(r'(?:utils\.minutes\((\d+)\)|(\d+))', value)
    if not found:
        raise ValueError('Non-literal numeric field: ' + name + '=' + value)
    return int(found[1]) * 60 if found[1] else int(found[2])


def enum_field(text, name, enums, prefix):
    value = field(text, name)
    found = re.fullmatch(re.escape(prefix) + r'\.([A-Z0-9_]+)', value)
    if not found or found[1] not in enums:
        raise ValueError('Unknown enum ' + name + ': ' + value)
    return enums[found[1]]


def pretty(name):
    value = name.replace('_', ' ').title()
    value = re.sub(r'\b(Sw|Nw|Se|Ne|Cs|Bcnm|Ksnm)\b', lambda match: match[0].upper(), value)
    return re.sub(r'(\d)(St|Nd|Rd|Th)\b', lambda match: match[1] + match[2].lower(), value)


def source_table(text, marker):
    try:
        return table_after(text, marker)
    except ValueError:
        return ''


def dataset(source, roots, path):
    result = source.yaml('data/' + path + '.yaml')
    for root in roots:
        overlay = root + '/' + path + '.yaml'
        if overlay in source.paths:
            result = merge_patch(result, source.yaml(overlay))
    return result


def npc_ids(source, roots, folder):
    values = dataset(source, roots, 'zones/' + folder.lower() + '/npcs').get('npcs', {})
    return {value.get('script', value.get('display_name')): nid for nid, value in values.items()}


def limbus_objectives(source, battle, area):
    """Keep route hints separate from progress the client has actually seen."""
    slug = battle['source'].rsplit('/', 1)[1][:-4]
    raw = source.read(battle['source']).split('content.loot =')[0]
    hints = {
        'nw_apollyon': [
            'Defeat Bardha until the vortex opens. Pluto reveals the item crate.',
            'Defeat Mountain Buffalo until the vortex opens. Zlatorog reveals the item crate.',
            'Defeat Apollyon Scavengers until the vortex opens. Millenary Mossback reveals the item crate.',
            'Defeat Gorynich until the vortex opens. Cynoprosopi reveals the item crate.',
            'Defeat Kaiser Behemoth, then open the loot crate.',
        ],
        'ne_apollyon': [
            'Defeat the selected boss to open the vortex. A different boss holds the item crate.',
            'Defeat Bialozar and Thiazi until the vortex opens. Bialozar Boss reveals the item crate.',
            'Defeat the selected Apollyon Sweeper to open the vortex. Enemy numbers depend on the alliance that registered.',
            'Defeat the selected giant to open the vortex. Kerkopes Boss reveals the item crate.',
            'Defeat all Troglodyte Dhalmel or both manticores, then open the loot crate.',
        ],
        'se_apollyon': [
            'Defeat Ghost Clot to open the vortex. Metalloid Amoeba deaths reveal crates.',
            'Defeat Tieholtsodi to open the vortex. Adamantshell deaths reveal crates.',
            'Defeat Grave Digger to open the vortex. Inhumer deaths reveal crates.',
            'Defeat all Evil Armory, then open the loot crate.',
        ],
        'sw_apollyon': [
            'Defeat Fir Bholg of the initiator\'s race. The first or final matching death opens the vortex; the other reveals crates.',
            'Defeat Jidra Boss to open the vortex. Further enemy deaths reveal crates.',
            'Reveal all disguised mimics to open the vortex. The three real crates are chosen for the run.',
            'Defeat the elementals matching the day recorded on arrival, then open the loot crate.',
        ],
    }
    if slug == 'temenos_northern_tower':
        hints[slug] = ['Defeat an eligible enemy to open the gate. Defeat the full floor group to reveal crates.'] * 6 + ['Defeat the final floor group, then open the loot crate.']
    elif slug == 'temenos_western_tower':
        hints[slug] = ['Defeat an enemy to open the gate. Further deaths may reveal one of the randomly assigned crates.'] * 6 + ['Defeat the final floor group, then open the loot crate.']
    elif slug == 'temenos_eastern_tower':
        hints[slug] = ['Defeat the elementals or their avatar. Choose one of the revealed crates to proceed; a crate may hold an avatar.'] * 6 + ['Defeat the final Dark Elementals or Mystic Avatar Fenrir. Open the item crate to finish.']
    floors = hints.get(slug, [battle['objective']['text']])
    battle['floors'] = {number: {'text': hint} for number, hint in enumerate(floors, 1)}
    battle['floor_count'] = len(floors)
    battle['objective']['text'] = floors[0] if len(floors) > 1 else battle['objective']['text']
    names = {}
    group_source = raw.split('content.groups =', 1)[-1]
    sections = list(re.finditer(r'-- Floor (\d+)\s*\r?$', group_source, re.M))
    for index, match in enumerate(sections):
        block = group_source[match.end():sections[index + 1].start() if index + 1 < len(sections) else len(group_source)]
        for group in re.findall(r'\bmobs\s*=\s*\{([^}]+)\}', without_comments(block)):
            for name in re.findall(r"'([^']+)'", group):
                names[name.replace('_', ' ')] = int(match[1])
    if slug == 'nw_apollyon':
        names.update(Pluto=1, Bardha=1)
    elif slug == 'ne_apollyon':
        names.update({'Apollyon Sweeper': 3, 'Apollyon Cleaner': 3})
    if slug == 'temenos_western_tower':
        names.update({name: floor for floor, name in enumerate(('Enhanced Tiger', 'Enhanced Mandragora', 'Enhanced Beetle', 'Enhanced Lizard', 'Enhanced Slime', 'Enhanced Pugil', 'Enhanced Vulture'), 1)})
    if slug == 'temenos_eastern_tower':
        names.update({name + ' Elemental E': floor for floor, name in enumerate(('Fire', 'Ice', 'Air', 'Earth', 'Thunder', 'Water', 'Dark'), 1)})
    names = {area['_aliases'].get(name.replace(' ', '_'), name): floor for name, floor in names.items()}
    battle['mob_floors'] = {nid: names[name] for nid, name in area['mobs'].items() if name in names and names[name] <= len(floors)}
    folder = battle['source'].split('/')[2]
    ids = source.read('scripts/zones/' + folder + '/IDs.lua')
    section = source_table(ids, re.escape(slug.upper()))
    portals = source_table(section, 'PORTAL')
    if portals:
        battle['portal_ids'] = {int(nid): floor for floor, nid in enumerate(re.findall(r'\b\d+\b', portals), 1)}


def build(source):
    init = source.read('modules/init.txt')
    roots = data_roots(init)
    zones = {key.upper(): value for key, value in source.yaml('data/enums/zone.yaml')['values'].items() if isinstance(value, int)}
    key_items = {key.upper(): value for key, value in source.yaml('data/enums/key_item.yaml')['values'].items() if isinstance(value, int)}
    items = numbers(source.read('scripts/enum/item.lua'))
    battlefield = source.read('scripts/globals/battlefield.lua')
    battle_ids = numbers(table_after(battlefield, r'xi\.battlefield\.id'))
    assault_enums = source.read('scripts/enum/assault.lua')
    mission_ids = numbers(table_after(assault_enums, r'xi\.assault\.mission'))
    instance_ids = numbers(table_after(assault_enums, r'xi\.assault\.instance'))
    area_ids = numbers(table_after(assault_enums, r'xi\.assault\.assaultArea'))
    shami = source.read('scripts/zones/Port_Jeuno/npcs/Shami.lua')
    orbs = {}
    for name, cs, option, seal, cost in re.findall(r'\[xi\.item\.([A-Z_]+)\s*\]\s*=\s*\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)', shami):
        if int(seal) > 1:
            continue
        orbs[items[name]] = {'name': pretty(name), 'seal': 'beastmen' if seal == '0' else 'kindred', 'cost': int(cost), 'option': int(option)}
    areas, item_catalog, wanted_mobs = {}, {}, {}

    def area(folder, zid):
        if zid not in areas:
            text = source.read('scripts/zones/' + folder + '/IDs.lua')
            messages = numbers(table_after(text, r'text'))
            mobdata = dataset(source, roots, 'zones/' + folder.lower() + '/mobs')
            aliases = {name: template.get('display_name', name).replace('_', ' ') for name, template in mobdata.get('templates', {}).items()}
            mobs = {mid: value.get('display_name', aliases.get(value.get('template', ''), value.get('template', ''))).replace('_', ' ') for mid, value in mobdata.get('spawns', {}).items()}
            areas[zid] = {'name': folder.replace('_', ' '), 'messages': messages, 'battles': {}, 'mobs': mobs, '_aliases': aliases,
                          '_templates': {mid: value.get('template') for mid, value in mobdata.get('spawns', {}).items()}}
            wanted_mobs[zid] = set()
        return areas[zid]

    def loot(text):
        result = sorted({items[name] for name in re.findall(r'itemId\s*=\s*xi\.item\.([A-Z0-9_]+)', without_comments(text)) if name in items and items[name] > 0})
        for name, value in items.items():
            if value in result:
                item_catalog[value] = {'name': pretty(name), 'kind': 'item'}
        return result

    paths = sorted(path for path in source.paths if path.startswith('scripts/battlefields/') and path.endswith('.lua'))
    for path in paths:
        text = without_comments(source.read(path))
        match = re.search(r'local content\s*=\s*(Battlefield|Limbus):new\(\s*\{', text)
        if not match:
            continue
        # Reuse the balanced table reader after the constructor's opening brace.
        config = table_after(text[match.start():].replace(':new(', ' = ', 1), r'(?:Battlefield|Limbus)')
        required = source_table(config, r'requiredKeyItems')
        alternatives = [re.findall(r'xi\.keyItem\.([A-Z0-9_]+)', group) for group in re.findall(r'\{([^{}]+)\}', required)]
        key_names = re.findall(r'xi\.keyItem\.([A-Z0-9_]+)', re.sub(r'\{[^{}]+\}', '', required))
        orb_names = re.findall(r'xi\.item\.([A-Z0-9_]+)', source_table(config, r'requiredItems'))
        orb = next((items[name] for name in orb_names if items.get(name) in orbs), None)
        group_key = next((name for name in key_names if name in ENM_KEYS), None)
        kind = 'limbus' if match[1] == 'Limbus' else 'enm' if group_key else orbs[orb]['seal'] if orb else None
        kind = {'beastmen': 'bcnm', 'kindred': 'ksnm'}.get(kind, kind)
        if kind is None:
            continue
        folder = path.split('/')[2]
        zid = enum_field(config, 'zoneId', zones, 'xi.zone')
        bid = enum_field(config, 'battlefieldId', battle_ids, 'xi.battlefield.id')
        index = integer(config, 'index')
        title_match = re.search(r'^-- (?:Name: )?([^\r\n]+)', source.read(path), re.M)
        name = pretty(path.rsplit('/', 1)[1][:-4])
        if title_match and not title_match[1].startswith(('Area:', '---', '!')):
            name = title_match[1]
        battle = {'id': bid, 'zone': zid, 'index': index, 'name': name, 'kind': kind,
                  'time_limit': integer(config, 'timeLimit'), 'level_cap': integer(config, 'levelCap', 0),
                  'max_players': integer(config, 'maxPlayers'), 'key_items': [key_items[name] for name in key_names],
                  'loot': loot(text), 'source': path}
        if alternatives:
            battle['key_item_options'] = [[key_items[name] for name in group] for group in alternatives]
        required_items = [items[name] for name in orb_names if name in items]
        if required_items:
            battle['entry_items'] = required_items
        if orb:
            battle['orb'] = orb
        if group_key:
            battle['enm_group'] = ENM_KEYS[group_key][0]
            battle['grant_xp'] = integer(config, 'grantXP', 0)
        if kind == 'limbus':
            battle['name'] = pretty(field(config, 'name').strip("'"))
            battle['time_extension'] = integer(config, 'timeExtension', 0) * 60
            battle['objective'] = {'type': 'unknown', 'text': 'Follow the route objectives. Open the final loot crate to finish.'}
        else:
            names = []
            for essential in re.findall(r':addEssentialMobs\(\s*\{([^}]+)\}', text):
                names.extend(re.findall(r"'([^']+)'", essential))
            battle['objective'] = {'type': 'unknown', 'text': 'Defeat the required enemies and open the Armoury Crate.'}
            if names:
                battle['objective']['mobs'] = dict(Counter(name.replace('_', ' ') for name in names))
                battle['objective']['text'] = 'Required enemies: ' + ', '.join(name.replace('_', ' ') for name in names) + '.'
        if index in area(folder, zid)['battles']:
            raise ValueError('Duplicate battlefield index: ' + path)
        area(folder, zid)['battles'][index] = battle
        if 'mobs' in battle['objective']:
            battle['objective']['mobs'] = {areas[zid]['_aliases'].get(name.replace(' ', '_'), name): count for name, count in battle['objective']['mobs'].items()}
        wanted_mobs[zid].update(value.replace('_', ' ') for value in re.findall(r"'([^']+)'", text))
        id_source = source.read('scripts/zones/' + folder + '/IDs.lua')
        id_names = dict(re.findall(r"\b([A-Z0-9_]+)\s*=\s*GetFirstID\('([^']+)'\)", id_source))
        for name in re.findall(r'\b(?:[A-Za-z]+ID|ID)\.mob\.([A-Z0-9_]+)', text):
            if name in id_names:
                wanted_mobs[zid].add(id_names[name].replace('_', ' '))
        if 'mobs' in battle['objective'] and kind in ('bcnm', 'ksnm'):
            counts = Counter(area(folder, zid)['mobs'].values())
            arenas = 1 if folder == 'Ghelsba_Outpost' else 3
            if all(counts[name] == count * arenas for name, count in battle['objective']['mobs'].items()):
                battle['objective']['type'] = 'kills'
                battle['objective']['required'] = sum(battle['objective']['mobs'].values())
        if kind == 'limbus':
            for name, job in re.findall(r'itemId\s*=\s*xi\.item\.([A-Z0-9_]+)[^\n]*--\s*(WAR|MNK|WHM|BLM|RDM|THF|PLD|DRK|BST|BRD|RNG|SAM|NIN|DRG|SMN|BLU|COR|PUP)\b', source.read(path)):
                if items.get(name) in item_catalog:
                    item_catalog[items[name]].update(kind='material', job=job)
            for name, set_name, piece, slot in re.findall(r'itemId\s*=\s*xi\.item\.([A-Z0-9_]+)[^\n]*--\s*(Homam|Nashira)\s+([^()\r\n]+)\s*\(([^)]+)\)', source.read(path)):
                if items.get(name) in item_catalog:
                    item_catalog[items[name]].update(kind='trophy', reward=set_name + ' ' + piece.strip(), slot=slot)

    # These routes have a fixed final boss, but earlier floors include random objectives.
    route_bosses = {'central_apollyon': 'Proto-Omega', 'central_temenos_4th_floor': 'Proto-Ultima'}
    for zone in areas.values():
        for battle in zone['battles'].values():
            slug = battle['source'].rsplit('/', 1)[1][:-4]
            if slug in route_bosses:
                boss = route_bosses[slug]
                if "'" + boss + "'" not in source.read(battle['source']):
                    raise ValueError('Limbus boss rule changed: ' + slug)
                battle['objective'] = {'type': 'kills', 'required': 1, 'mobs': {boss: 1}, 'text': 'Defeat ' + boss + ', then open the loot crate.'}
            elif slug == 'central_temenos_1st_floor':
                names = ('Airi', 'Temenos Cleaner', 'Iruci', 'Temenos Weapon', 'Enhanced Dragon', 'Enhanced Ahriman')
                battle['objective'] = {'type': 'kills', 'required': 6, 'mobs': {name: 1 for name in names}, 'text': 'Defeat all six enemies, then open the loot crate. Each death strengthens its surviving partner.'}
            elif slug == 'central_temenos_2nd_floor':
                boss_ids = {nid: True for nid, template in zone['_templates'].items() if template == 'Mystic_Avatar_Carbuncle'}
                if len(boss_ids) != 1:
                    raise ValueError('Central Temenos Carbuncle placement changed.')
                battle['objective'] = {'type': 'kills', 'required': 1, 'mobs': {'Mystic Avatar': 1}, 'mob_ids': boss_ids,
                                       'text': 'Defeat Mystic Avatar Carbuncle, then open the loot crate. The elemental route changes which avatars appear.'}
            elif slug == 'central_temenos_3rd_floor':
                names = ('Abyssdweller Jhabdebb', 'Orichalcum Quadav', 'Pee Qoho the Python')
                battle['objective'] = {'type': 'kills', 'required': 3, 'mobs': {name: 1 for name in names}, 'text': 'Defeat the three beastmen bosses, then open the loot crate.'}
            elif slug == 'central_temenos_basement':
                battle['objective'] = {'type': 'kills', 'required': 1, 'mobs': {'Temenos Ghrah': 1}, 'text': 'Defeat the Aern through their reraises. Temenos Ghrah appears after the last Aern is fully gone. Defeat it and open the loot crate.'}
            elif slug == 'cs_apollyon':
                names = ('Carnagechief Jackbodokk', 'NaQba Chirurgeon', 'Dee Wapa the Desolator')
                battle['objective'] = {'type': 'kills', 'required': 3, 'mobs': {name: 1 for name in names}, 'text': 'Defeat all three beastmen bosses, then open the loot crate. The first two boss deaths each reveal a time crate.'}
            if slug == 'undying_promise':
                battle['objective'] = {'type': 'unknown', 'text': 'Enemies return after defeat. Open the Armoury Crate after the final death.'}
            elif slug == 'when_hell_freezes_over':
                assert "getLocalVar('wave') >= 4" in source.read(battle['source'])
                battle['objective'] = {'type': 'waves', 'required': 4, 'mobs': {'Snow Devil': True},
                                       'mob_ids': {nid: True for nid, name in zone['mobs'].items() if name == 'Snow Devil'},
                                       'text': 'Defeat four waves of Snow Devils. Each wave has one to three enemies.'}
            elif slug == 'fire_in_the_sky':
                battle['objective'] = {'type': 'unknown', 'text': 'Defeat Razon without allowing self-destruct, then open the Armoury Crate.'}
            elif slug == 'royale_ramble':
                battle['objective'] = {'type': 'unknown', 'text': 'Defeat the Cardians, including the reinforcements, then open the Armoury Crate.'}
            if battle['kind'] == 'limbus':
                limbus_objectives(source, battle, zone)

    assault_missions = {}
    instances = source.read('sql/instance_list.sql')
    instance_times = {int(iid): int(minutes) * 60 for iid, minutes in re.findall(r"VALUES\s*\((\d+),'[^']+',\d+,\d+,NULL,\s*(\d+),", instances)}
    for path in sorted(path for path in source.paths if path.startswith('scripts/assaults/') and path.endswith('.lua') and path.rsplit('/', 1)[1][:-4] in ASSAULTS):
        raw = source.read(path)
        text = without_comments(raw)
        config = table_after(text.replace(':new(', ' = ', 1), r'InstanceAssault')
        zid = enum_field(config, 'zoneID', zones, 'xi.zone')
        mid = enum_field(config, 'assaultID', mission_ids, 'xi.assault.mission')
        folder = path.split('/')[2]
        objective = re.search(r'-- Objective:\s*([^\r\n]+)', raw)
        mission = {'id': mid, 'index': mid, 'instance': enum_field(config, 'instanceID', instance_ids, 'xi.assault.instance'),
                   'zone': zid, 'name': pretty(path.rsplit('/', 1)[1][:-4]), 'kind': 'assault',
                   'area': enum_field(config, 'assaultArea', area_ids, 'xi.assault.assaultArea'),
                   'time_limit': instance_times[enum_field(config, 'instanceID', instance_ids, 'xi.assault.instance')], 'level_cap': 0, 'max_players': 6,
                   'suggested_level': integer(config, 'suggestedLevel'),
                   'key_items': [enum_field(config, 'requiredOrders', key_items, 'xi.keyItem')],
                   'base_points': integer(config, 'basePoints'), 'loot': loot(text), 'source': path,
                   'objective': {'type': 'unknown', 'text': objective[1] if objective else 'Complete the mission objective, then use the Rune of Release.'}}
        if mid == 1:
            mission['objective'].update(type='kills', required=integer(config, 'requiredProgress'), mobs={'Leujaoam Worm': 15})
        elif mid == 21:
            mission['objective'].update(type='rocks', required=integer(config, 'requiredProgress'), mobs={'Brittle Rock': 5})
        assault_missions[mid] = mission
        area(folder, zid).update(kind='assault', missions={mid: True}, battles={mid: mission})
        if mid == 1:
            wanted_mobs[zid].add('Leujaoam Worm')
        elif mid == 21:
            wanted_mobs[zid].add('Brittle Rock')
            rock = source.read('scripts/zones/Lebros_Cavern/mobs/Brittle_Rock.lua')
            assert 'rockOffset == 9' in rock and 'DespawnMob(mob:getID() - 1, instance)' in rock
            rock_ids = sorted(nid for nid, name in areas[zid]['mobs'].items() if name == 'Brittle Rock')
            if len(rock_ids) == 10:
                mission['objective']['mob_ids'] = {nid: True for nid in rock_ids[1::2]}
        else:
            # The mission text confirms these objectives; hidden or random targets stay unknown.
            wanted_mobs[zid].update(areas[zid]['mobs'].values())

    # Apply the loaded Phoenix text-ID corrections, never the unused documentation copies.
    overrides = source.read('modules/phoenix/lua/custom/limbus_text_ids.lua')
    for prefix, zid in (('temenos', zones['TEMENOS']), ('apollyon', zones['APOLLYON'])):
        for key, value in re.findall(prefix + r'\.text\.([A-Z_]+)\s*=\s*(\d+)', overrides):
            areas[zid]['messages'][key] = int(value)
    source.read('modules/phoenix/lua/battlefields/up_in_arms_kraken_club.lua')
    settings = source.read('settings/default/main.lua')
    enm_seconds = integer(settings, 'ENM_COOLDOWN') * 3600
    enm_groups = {value[0]: {'id': value[0], 'name': value[1], 'ready_var': value[2], 'key_items': [key_items[key]],
                           'duration': enm_seconds, 'trigger': 'key_item_obtained', 'scope': 'character'}
                  for key, value in ENM_KEYS.items() if key in key_items}
    cooldown_paths = ('Attohwa_Chasm/npcs/Jakaka', 'Lower_Jeuno/npcs/Ghebi_Damomohe', 'Oldton_Movalpolos/npcs/Twinkbrix',
                      'RuLude_Gardens/npcs/Venessa', 'Tavnazian_Safehold/npcs/Morangeart', 'Uleguerand_Range/npcs/Zebada')
    for path in cooldown_paths:
        source.read('scripts/zones/' + path + '.lua')
    limits = source.read('modules/phoenix/lua/quests/assault_limits.lua')
    assert 'maxAssaultRank   = xi.assault.mercenaryRank.PRIVATE_SECOND_CLASS' in limits
    source.read('scripts/globals/assault/container.lua')
    source.read('scripts/globals/assault/npc_handler.lua')
    enm = source.read('scripts/globals/enm.lua')
    enm_npcs = {}
    for name, intro, repeat, default in re.findall(r"\['([^']+)'\s*\]\s*=\s*\{ introduction =\s*(\d+), recurring =\s*(\d+), default =\s*(\d+)", enm):
        folder = {'Moritz': 'Upper_Jeuno', 'Ophelia': 'Southern_San_dOria', 'Gregory': 'Bastok_Mines', 'Istvan': 'Windurst_Woods'}[name]
        enm_npcs.setdefault(zones[folder.upper()], {})[npc_ids(source, roots, folder)[name]] = {
            'name': name, 'events': {int(intro): True, int(repeat): True}, 'options': {key: key for key in enm_groups}}
    limbus = source.read('scripts/globals/limbus.lua')
    sagheera = source.read('scripts/zones/Port_Jeuno/npcs/Sagheera.lua')
    assert "player:setCharVar('Cosmo_Cleanse_TIME', GetSystemTime())" in limbus
    assert 'and 3600 or 72000' in sagheera
    cooldowns = {'enm': {'duration': enm_seconds, 'trigger': 'key_item_obtained', 'scope': 'character'},
                 'limbus': {'duration': 72000, 'trigger': 'battlefield_entry', 'scope': 'character'}}
    dynamis = source.read('scripts/globals/dynamis/dyna_lockout.lua')
    assert "getAccountVar('[DYNA]lockout')" in dynamis and 'local lockoutInHours = 72' in dynamis
    registration = source.read('scripts/globals/dynamis/dynamis_system.lua')
    assert 'xi.dynamis.registerPlayer = function' in registration and 'xi.dynamis.recordLockout(player)' in registration
    cooldowns['dynamis'] = {'duration': 72 * 3600, 'trigger': 'registration', 'scope': 'account'}
    for zid, value in areas.items():
        wanted = {value['_aliases'].get(name.replace(' ', '_'), name) for name in wanted_mobs[zid]}
        value['mobs'] = {nid: name for nid, name in value['mobs'].items() if name in wanted}
        del value['_aliases']
        del value['_templates']
    for item in item_catalog:
        if item == items['ANCIENT_BEASTCOIN']:
            item_catalog[item]['kind'] = 'coin'
        elif item_catalog[item]['name'].endswith(' Chip'):
            item_catalog[item]['kind'] = 'chip'
    for item, orb in orbs.items():
        item_catalog.setdefault(item, {'name': orb['name'], 'kind': 'orb'})
    seals = source.read('scripts/globals/seals.lua')
    seal_items, seal_retrieval = {}, {}
    for name, seal_id, option in re.findall(r'\[xi\.item\.([A-Z_]+)\s*\]\s*=\s*\{\s*(\d+),\s*(\d+)', seals):
        if int(seal_id) < 2:
            family = 'beastmen' if seal_id == '0' else 'kindred'
            seal_items[family], seal_retrieval[family] = items[name], int(option)
    shami_events = {}
    for name, pattern in {
            'event': r'player:startEvent\((\d+),\s*\(kindredsSeal \* 65536\) \+ beastmensSeal',
            'deposit_event': r'local eventParams = \{\s*(\d+),',
            'empty_event': r'== 0 then\s+player:startEvent\((\d+)\)',
    }.items():
        match = re.search(pattern, without_comments(shami))
        if not match:
            raise ValueError('Missing Shami event contract: ' + name)
        shami_events[name] = int(match[1])
    if 'bit.lshift(storedSeals + itemCount, 16)' not in seals:
        raise ValueError('Shami deposit balance packing changed.')
    port_text = numbers(table_after(source.read('scripts/zones/Port_Jeuno/IDs.lua'), r'text'))
    npc_util = source.read('scripts/globals/npc_util.lua')
    quantity_message = re.search(r'ID\.text\.ITEM_OBTAINED\s*\+\s*(\d+)', npc_util)
    if not quantity_message:
        raise ValueError('Missing confirmed item quantity message.')
    shami_events.update(zone=zones['PORT_JEUNO'], id=npc_ids(source, roots, 'Port_Jeuno')['Shami'],
                        item_obtained=port_text['ITEM_OBTAINED'],
                        item_obtained_count=port_text['ITEM_OBTAINED'] + int(quantity_message[1]),
                        inventory_full=port_text['ITEM_CANNOT_BE_OBTAINED'])
    for path in ('src/map/packets/s2c/0x032_event.h', 'src/map/packets/c2s/0x05b_eventend.h'):
        source.read(path)
    result = {'source_ref': source.ref, 'areas': areas, 'assault_missions': assault_missions,
              'enm_groups': enm_groups, 'enm_npcs': enm_npcs, 'cooldowns': cooldowns, 'orbs': orbs, 'items': item_catalog,
              'seal_items': seal_items, 'seal_retrieval': seal_retrieval,
              'key_items': {key: key_items[key] for key in sorted(set(ENM_KEYS) | {'COSMO_CLEANSE', 'RED_CARD', 'BLACK_CARD', 'WHITE_CARD', 'IMPERIAL_ARMY_ID_TAG'}) if key in key_items},
              'npcs': {'shami': shami_events,
                       'sagheera': {'zone': zones['PORT_JEUNO'], 'id': npc_ids(source, roots, 'Port_Jeuno')['Sagheera'], 'event': 310},
                       'rytaal': {'zone': zones['AHT_URHGAN_WHITEGATE'], 'id': npc_ids(source, roots, 'Aht_Urhgan_Whitegate')['Rytaal'], 'event': 268}}}
    used_key_items = set(result['key_items'].values())
    for zone in areas.values():
        for battle in zone['battles'].values():
            used_key_items.update(battle['key_items'])
            for group in battle.get('key_item_options', []):
                used_key_items.update(group)
    result['key_item_names'] = {value: pretty(name).replace('Cosmo Cleanse', 'Cosmo-Cleanse') for name, value in key_items.items() if value in used_key_items}
    basic = numbers(table_after(source.read('scripts/enum/msg.lua'), r'xi\.msg\.basic'))
    result['basic_messages'] = {'TIME_LEFT': basic['TIME_LEFT']}
    result['source_sha256'] = {path: hashlib.sha256(text.encode('utf8')).hexdigest() for path, text in sorted(source.texts.items())}
    return result


def render(repo, ref=PINNED_REF):
    return '-- Phoenix event rules. Refresh with tools/export_events.py.\nreturn ' + lua(build(Source(repo, ref))) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path, help='Phoenix checkout; reads Git objects only.')
    parser.add_argument('--ref', default=PINNED_REF)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    output = render(args.source, args.ref)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding='utf8') != output:
            raise SystemExit('Event data is out of date. Run the exporter without --check.')
        print('Phoenix event data matches the pinned source.')
    else:
        OUTPUT.write_text(output, encoding='utf8', newline='\n')
        print('Exported Phoenix event rules to momentum/data/event_rules.lua.')


if __name__ == '__main__':
    main()
